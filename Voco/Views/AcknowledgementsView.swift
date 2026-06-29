//
//  AcknowledgementsView.swift
//  HexIOS
//
//  Third-party attribution screen. Voco is closed-source and built on Hex (MIT).
//  Lists every bundled SPM dependency with its verbatim license text. Data comes
//  from the generated `Acknowledgements.all` (AcknowledgementsData.swift).
//

import SwiftUI

struct AcknowledgementsView: View {
    var body: some View {
        List {
            Section {
                Text("Voco is built on Hex (MIT) and the open-source and licensed components below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(Acknowledgements.all) { item in
                    NavigationLink {
                        AcknowledgementDetailView(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text(item.license)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AcknowledgementDetailView: View {
    let item: Acknowledgement
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.title3.weight(.semibold))
                    if !item.version.isEmpty {
                        Text("Version \(item.version)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.license)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let url = URL(string: item.url), !item.url.isEmpty {
                        Button {
                            openURL(url)
                        } label: {
                            Text(item.url)
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }

                Divider()

                Text(item.text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
