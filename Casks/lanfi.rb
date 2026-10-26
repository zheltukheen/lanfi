cask "lanfi" do
  version "2.6.0"
  sha256 "4fc0e6b9ba4e4401e8ce3b7b34fbfb805b92e252398cfa7b727d3a29d1084a4c"

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
