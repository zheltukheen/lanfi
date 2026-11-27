cask "lanfi" do
  version "5.7.1"
  sha256 "f9285252d4a0bf27a63b2176c672579d93f09f328070123fac392645f7f62e6b"

  url "https://github.com/zheltukheen/lanfi/releases/download/v#{version}/LanFi.dmg"
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
