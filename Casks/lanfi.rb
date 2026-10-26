cask "lanfi" do
  version "2.3.0"
  sha256 "9a219393bb743663f15d02b93a373ae5bd0e26453504d8d2e384043c754b72c0"

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
