cask "wifa" do
  version "1.4.0"
  sha256 "533b38686c7be7c3710cf570a90ad336ea67870de020b9d8f7c272bf91b2623b"

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
