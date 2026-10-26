cask "wifa" do
  version "1.5.0"
  sha256 "b18e75e1ef9f42826a0b1137614e12d1f00e5d9fc11328f797c2fd7d1f21e48d"

  url "https://github.com/zheltukheen/wifa/releases/download/v#{version}/WiFA-#{version}.dmg"
  name "WiFA"
  desc "Native Wi-Fi analyzer with quality, channel and security diagnostics"
  homepage "https://github.com/zheltukheen/wifa"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "WiFA.app"

  zap trash: [
    "~/Library/Application Support/WiFA",
    "~/Library/Preferences/ru.zheltukheen.WiFA.plist",
    "~/Library/Caches/ru.zheltukheen.WiFA",
  ]
end
