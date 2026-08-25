# Distribution

## Homebrew cask

[`Casks/whisk.rb`](Casks/whisk.rb) is the template for the live cask in
[`alexnodeland/homebrew-tap`](https://github.com/alexnodeland/homebrew-tap).
The tap uses **pinned** `version` + `sha256` casks (its README explains why:
`brew upgrade` skips `:latest` casks, and the checksum is the only integrity
check for unsigned apps), auto-bumped twice daily by the tap's
`scripts/bump.py` cron against the stable-named `Whisk-universal.zip` release
asset.

**One-time publish (after the first tagged release):**

```bash
VERSION=0.1.0
curl -sL "https://github.com/alexnodeland/whisk/releases/download/v${VERSION}/Whisk-universal.zip" \
  | shasum -a 256          # fill version + sha256 into the cask
cp dist/Casks/whisk.rb ../homebrew-tap/Casks/whisk.rb
# edit the two lines, then commit in the tap:  whisk: v0.1.0
```

Every later release is picked up by the cron automatically. Users install with:

```bash
brew tap alexnodeland/tap
brew install --cask whisk
```

## Cutting a release

```bash
git tag v0.1.0 && git push origin v0.1.0    # triggers .github/workflows/release.yml
```

The workflow builds a universal (arm64 + x86_64) binary and attaches both
`Whisk-<version>.zip` and `Whisk-universal.zip` to the GitHub Release.
Signing/notarization run when the `CODESIGN_IDENTITY` / `NOTARIZE_*` secrets
exist and degrade gracefully to an ad-hoc build when absent; an Ed25519
`.sig` for the future updater (ADR 0009) is published when
`UPDATE_SIGNING_KEY` is set.
