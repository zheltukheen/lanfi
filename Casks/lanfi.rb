cask "lanfi" do
  version "5.5.0"
  sha256 "78b9cb5b582dcfbab6469d0d2724b0bf7b7cd574e55ffb3f2073e1f49bd0d0be"

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
