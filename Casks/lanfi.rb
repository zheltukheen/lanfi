cask "lanfi" do
  version "4.0.0"
  sha256 "6c516de3a707e40bd7217c86ac3e72663e207fd449c904c9012a5235a250936b"

  url "https://github.com/zheltukheen/lanfi/releases/download/v#{version}/LanFi-#{version}.dmg"
  name "LanFi"
  desc "Native Wi-Fi analyzer with quality, channel and security diagnostics"
  homepage "https://github.com/zheltukheen/lanfi"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "LanFi.app"

  zap trash: [
    "~/Library/Application Support/LanFi",
    "~/Library/Preferences/ru.zheltukheen.LanFi.plist",
    "~/Library/Caches/ru.zheltukheen.LanFi",
  ]
end
