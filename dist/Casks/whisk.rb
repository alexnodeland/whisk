# Template for the live cask in alexnodeland/homebrew-tap (ADR 0011).
#
# The version and sha256 below are deliberately-drifting placeholders: the
# tap's copy is bumped automatically by its scripts/bump.py cron, which parses
# the `version`, `sha256`, and `url` lines — keep those three lines' shapes
# stable. Publish flow: after the first tagged release, copy this file into
# the tap with the real version and sha256 (see ../README.md).
cask "whisk" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/alexnodeland/whisk/releases/download/v#{version}/Whisk-universal.zip"
  name "Whisk"
  desc "Menu bar utility that keeps folders clean with user-defined rules"
  homepage "https://github.com/alexnodeland/whisk"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on :macos

  app "Whisk.app"

  zap trash: [
    "~/.config/whisk",
    "~/Library/Application Support/Whisk",
    "~/Library/Preferences/com.alexnodeland.whisk.plist",
  ]

  caveats <<~EOS
    Whisk is not yet signed or notarized. If macOS blocks the first launch:
      xattr -dr com.apple.quarantine "#{appdir}/Whisk.app"
  EOS
end
