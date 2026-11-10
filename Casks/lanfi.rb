cask "lanfi" do
  version "4.12.1"
  sha256 "fe5880093521539839dd615b3fa13e0df5b2815b9b90299376bc8e441266bdd6"

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
