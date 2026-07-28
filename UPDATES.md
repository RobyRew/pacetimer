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

## Per-app signing keys

Sparkle's default is **one key per developer** (`generate_keys` with no arguments
reuses whatever is already in the Keychain, and never overwrites it). This project
instead uses a **dedicated key per app** via `--account`, so a leaked key only ever
affects one app:

| App | Keychain account | Public key (in its `Info.plist`) |
|---|---|---|
| PeaceTimer | `PeaceTimer` | `md3JMF+GB9+7tY+7+pxvuo1f1APzC9vPiHy99wyvOWQ=` |
| TopPresenter | *(default)* | `4X2KEouvDSSL8Yyj8xr8OmxVFnGGSk1L2olrXkkm8CM=` |

Create a key for a new app with:
```sh
./bin/generate_keys --account <AppName>
```

## One-time steps (PeaceTimer)

1. **Key pair** — ✅ already done (Keychain account `PeaceTimer`).
2. **Public key in `Info.plist`** — ✅ already set (`SUPublicEDKey` above).
3. **Export the private key → repo secret** (the one manual step; Keychain will ask
   for your approval, which is why it can't be automated):
   ```sh
   ./bin/generate_keys --account PeaceTimer -x k.txt
   gh secret set SPARKLE_PRIVATE_KEY -R RobyRew/pacetimer < k.txt
   rm k.txt
   ```
   ⚠️ Use `--account PeaceTimer` — without it you'd export the *default* key, which
   does **not** match the public key baked into this app, and every update would
   fail signature verification.
4. **Enable GitHub Pages** for the repo: Settings → Pages → Source = **GitHub Actions**.

That's it. The appcast steps in CI are gated on `SPARKLE_PRIVATE_KEY` — until the
secret exists they no-op and the build stays green.

## User-facing controls

- **Settings ▸ Updates** — "Check Now", automatic-check toggle, current version,
  last-checked time.
- Scheduled checks run on launch and every `SUScheduledCheckInterval` seconds
  (default 24h). Silent auto-download is off by default (`SUAutomaticallyUpdate`).
