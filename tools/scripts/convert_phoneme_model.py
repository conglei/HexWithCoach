#!/usr/bin/env python3
"""
Convert a wav2vec2 phoneme-CTC model to Core ML for on-device forced alignment.

This is the "model side" of the pronunciation-coach spike. The Swift side
(`CTCForcedAligner` in HexCore) consumes the per-frame phoneme log-probs this
model produces and aligns them to a known phoneme sequence.

⚠️ Run this on a Mac with a real ML Python env (NOT the app sandbox). Requires:
    python3.11 or 3.12  (coremltools/torch wheels lag the newest Python)
    pip install torch transformers coremltools

Usage:
    python convert_phoneme_model.py \
        --model facebook/wav2vec2-lv-60-espeak-cv-ft \
        --out PhonemeCTC.mlpackage

Recommended English models:
    facebook/wav2vec2-lv-60-espeak-cv-ft   # IPA phonemes (~317M, ~315MB INT8)
    vitouphy/wav2vec2-xls-r-300m-timit-phoneme  # TIMIT/ARPAbet (~300M)
    (a wav2vec2-base phoneme model if you want ~95MB)

Outputs:
    <out>                 the Core ML package (mlprogram, FP16)
    <out>.vocab.json      {id: phoneme} so Swift can map label indices → symbols
"""
import argparse, json, os
import torch
import coremltools as ct
from transformers import AutoModelForCTC
from huggingface_hub import hf_hub_download


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", default="PhonemeCTC.mlpackage")
    # Enumerated audio lengths (samples @16kHz) keep the model on the ANE instead
    # of stalling on dynamic shapes. ~2s / ~5s / ~10s covers note-sized clips.
    ap.add_argument("--lengths", default="32000,80000,160000")
    # Flexible mode accepts ANY length in [min,max] samples — easier to integrate
    # (no padding to fixed buckets) at the cost of possibly not staying on the ANE.
    ap.add_argument("--flexible", action="store_true")
    ap.add_argument("--flex-range", default="16000,480000")  # 1s .. 30s
    # Fixed mode: a single static input length (samples). Static shapes are what let
    # the GPU/ANE run the model — dynamic/enumerated shapes only run on CPU on device.
    ap.add_argument("--fixed", type=int, default=0)
    args = ap.parse_args()

    model = AutoModelForCTC.from_pretrained(args.model).eval()

    # Read the phoneme vocab directly from the repo's vocab.json. We avoid
    # AutoProcessor because the phoneme tokenizer instantiates an espeak/phonemizer
    # backend on load — that's a G2P concern for *inference*, not for converting the
    # acoustic model or reading its label set.
    with open(hf_hub_download(args.model, "vocab.json")) as f:
        token_to_id = json.load(f)
    id_to_token = {i: t for t, i in token_to_id.items()}
    blank_id = model.config.pad_token_id
    if blank_id is None:
        blank_id = token_to_id.get("<pad>", token_to_id.get("[PAD]"))

    # Wrap so the Core ML model emits log-probabilities directly (what the Swift
    # aligner wants); avoids a softmax reimplementation on device.
    class LogProbCTC(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, input_values):  # (1, samples) float32 @16kHz, normalized
            logits = self.m(input_values).logits  # (1, frames, vocab)
            return torch.log_softmax(logits, dim=-1)

    wrapper = LogProbCTC(model).eval()
    lengths = [args.fixed] if args.fixed else [int(x) for x in args.lengths.split(",")]
    example = torch.zeros(1, lengths[0])
    traced = torch.jit.trace(wrapper, example)

    if args.fixed:
        # Single static shape — the accelerator-friendly form (GPU/ANE can plan it).
        input_shape = ct.Shape(shape=(1, args.fixed))
    elif args.flexible:
        lo, hi = (int(x) for x in args.flex_range.split(","))
        input_shape = ct.Shape(shape=(1, ct.RangeDim(lower_bound=lo, upper_bound=hi, default=lengths[0])))
        lengths = [lo, hi]  # record the range in meta
    else:
        input_shape = ct.EnumeratedShapes(shapes=[ct.Shape(shape=(1, n)) for n in lengths])

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input_values", shape=input_shape)],
        outputs=[ct.TensorType(name="log_probs")],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )
    mlmodel.save(args.out)

    # Persist the vocabulary so Swift can map label indices → phoneme symbols and
    # find the CTC blank id.
    meta = {
        "vocab": id_to_token,
        "blank_id": blank_id,
        "frame_stride_seconds": 0.02,  # wav2vec2 = 20ms
        "sample_rate": 16000,
        "enumerated_lengths": lengths,
    }
    with open(args.out + ".vocab.json", "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)

    print(f"✓ wrote {args.out} and {args.out}.vocab.json ({len(id_to_token)} phonemes)")
    print("  Next: drop the .mlpackage into the iOS app, feed 16kHz mono samples,")
    print("  take the log_probs output into CTCForcedAligner.align(...).")


if __name__ == "__main__":
    main()
