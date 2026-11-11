cask "lanfi" do
  version "4.13.0"
  sha256 "53281d1eca22dfcd503642a2d0962c538eb19cad33038d6bb3dbbffb3ae459ae"

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
