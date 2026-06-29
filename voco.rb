cask "voco" do
  version "0.2.11"
  sha256 :no_check  # Will be filled after first release

  url "https://voco-updates.s3.amazonaws.com/Voco-#{version}.dmg"
  name "Voco"
  desc "On-device voice-to-text for macOS"
  homepage "https://voco-updates.s3.amazonaws.com/appcast.xml"

  livecheck do
    url "https://voco-updates.s3.amazonaws.com/appcast.xml"
    strategy :sparkle
  end

  auto_updates true
  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

  app "Voco.app"

  zap trash: [
    "~/Library/Application Support/co.stonefrontier.voco",
    "~/Library/Caches/co.stonefrontier.voco",
    "~/Library/Containers/co.stonefrontier.voco",
    "~/Library/Preferences/co.stonefrontier.voco.plist",
  ]
end
