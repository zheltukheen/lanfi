cask "lanfi" do
  version "4.2.0"
  sha256 "8e3112f8ff8efb33dd8a8b3f786c6eb5855f567582e2d2922b9066bca674b317"

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
