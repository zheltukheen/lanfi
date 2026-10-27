cask "lanfi" do
  version "3.1.1"
  sha256 "45095c3cdd83fd998e5b9b3e4eea64d0399d3b2e71dbdd3cac17781b19629feb"

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
