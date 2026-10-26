cask "lanfi" do
  version "2.5.4"
  sha256 "fc8c0493cf51f9c8082a5dc202ce0932034e3ff167256980953586b7c5f87451"

  url "https://github.com/zheltukheen/wifa/releases/download/v#{version}/LanFi-#{version}.dmg"
  name "LanFi"
  desc "Native Wi-Fi analyzer with quality, channel and security diagnostics"
  homepage "https://github.com/zheltukheen/wifa"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "LanFi.app"

  zap trash: [
    "~/Library/Application Support/LanFi",
    "~/Library/Application Support/WiFA",
    "~/Library/Preferences/ru.zheltukheen.WiFA.plist",
    "~/Library/Caches/ru.zheltukheen.WiFA",
  ]
end
