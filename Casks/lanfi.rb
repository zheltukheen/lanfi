cask "lanfi" do
  version "4.4.1"
  sha256 "483b74b5f7491a2bff5fe5e2524b2e198b4c87aa89c556253f437bd6cc8f4d6f"

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
