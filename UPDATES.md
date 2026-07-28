# Auto-updates (Sparkle) — one-time setup

PeaceTimer ships with [Sparkle](https://sparkle-project.org) wired in, but the
updater stays **dormant** until you add a signing key. Everything below is done
once; after that, every push to `main` publishes a signed update automatically.

## How it works

- The app reads its feed from `SUFeedURL` (`Info.plist`) →
  `https://robyrew.github.io/pacetimer/appcast.xml`.
- CI (`.github/workflows/build-and-release.yml`) builds the app, EdDSA-signs the zip,
  regenerates `appcast.xml`, and deploys it to **GitHub Pages** — no `gh-pages`
  branch, the feed is deployed straight from the Actions run.
- Sparkle verifies each update's EdDSA signature against `SUPublicEDKey` before
  installing, so a compromised download can't be pushed to users.

## One-time steps

1. **Generate a key pair** (needs Sparkle's tools once, locally):
   ```sh
   # download Sparkle release, then:
   ./bin/generate_keys
   ```
   It prints a **public** key and stores the **private** key in your login Keychain.

2. **Add the public key to `Info.plist`** — replace the placeholder:
   ```xml
   <key>SUPublicEDKey</key>
   <string>REPLACE_WITH_YOUR_SPARKLE_ED_PUBLIC_KEY</string>
   ```
   (`UpdateController` keeps Sparkle asleep while this is the placeholder, so the
   app is safe to ship before you're ready.)

3. **Export the private key and add it as a repo secret**:
   ```sh
   ./bin/generate_keys -x sparkle_private_key.txt
   ```
   In GitHub → Settings → Secrets and variables → Actions, add
   **`SPARKLE_PRIVATE_KEY`** with that value, then delete the local file.

4. **Enable GitHub Pages** for the repo: Settings → Pages → Source = **GitHub Actions**.

That's it. The appcast steps in CI are gated on `SPARKLE_PRIVATE_KEY` — until the
secret exists they no-op and the build stays green.

## User-facing controls

- **Settings ▸ Updates** — "Check Now", automatic-check toggle, current version,
  last-checked time.
- Scheduled checks run on launch and every `SUScheduledCheckInterval` seconds
  (default 24h). Silent auto-download is off by default (`SUAutomaticallyUpdate`).
