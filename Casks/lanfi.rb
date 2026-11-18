cask "lanfi" do
  version "5.4.0"
  sha256 "cafa5a1985e5d7a7a6773c46e15fafcff9a32b1a2022dbaa47df71cef8401fa7"

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
