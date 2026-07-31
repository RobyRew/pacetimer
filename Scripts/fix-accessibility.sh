#!/usr/bin/env bash
#
# fix-accessibility.sh — stop macOS re-asking for Accessibility on every build/update.
#
# WHY IT KEEPS ASKING
#   TCC (the privacy database) identifies an app by its CODE SIGNATURE, not by name
#   or path. Builds from CI are signed "ad-hoc", whose identity is derived from the
#   binary's hash — so every new build is a brand-new app as far as macOS is
#   concerned. The permission you granted last time belongs to the previous binary,
#   which is why Settings shows it enabled while the app still asks.
#
# WHAT THIS DOES
#   Re-signs the app (inside-out, including the nested Sparkle helpers) with your
#   stable "Apple Development" identity, clears the stale TCC entry, and leaves you
#   to grant it once. From then on the grant survives future updates, as long as
#   they're re-signed with the same identity.
#
# USAGE
#   ./Scripts/fix-accessibility.sh [/path/to/PeaceTimer.app]
#   (defaults to /Applications/PeaceTimer.app)

set -euo pipefail

APP="${1:-/Applications/PeaceTimer.app}"
BUNDLE_ID="com.robyrew.peacetimer"

[ -d "$APP" ] || { echo "❌ Not found: $APP"; echo "   Drag PeaceTimer into /Applications first, or pass the path."; exit 1; }

# Pick the first available Apple Development / Developer ID identity.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | grep -oE '"(Apple Development|Developer ID Application)[^"]*"' | head -1 | tr -d '"')}"

[ -n "$IDENTITY" ] || { echo "❌ No codesigning identity found. Open Xcode → Settings → Accounts and add your Apple ID."; exit 1; }
echo "▸ Signing identity: $IDENTITY"

echo "▸ Quitting the app if it's running…"
osascript -e "tell application \"$(basename "$APP" .app)\" to quit" 2>/dev/null || true
sleep 1

# Sign nested code FIRST (inside-out), then the bundle itself. Signing the outer
# bundle before its nested helpers produces an invalid signature.
SPK="$APP/Contents/Frameworks/Sparkle.framework"
for target in \
  "$SPK/Versions/B/XPCServices/Downloader.xpc" \
  "$SPK/Versions/B/XPCServices/Installer.xpc" \
  "$SPK/Versions/B/Autoupdate" \
  "$SPK/Versions/B/Updater.app" \
  "$SPK"; do
  [ -e "$target" ] && codesign --force --sign "$IDENTITY" --timestamp=none \
      --preserve-metadata=entitlements "$target" >/dev/null 2>&1 || true
done

echo "▸ Signing the app…"
codesign --force --sign "$IDENTITY" --timestamp=none \
    --preserve-metadata=entitlements "$APP"

echo "▸ Verifying…"
codesign --verify --deep --strict "$APP" && echo "  signature OK"
codesign -dv "$APP" 2>&1 | grep -E 'Signature|TeamIdentifier' | sed 's/^/  /'

echo "▸ Clearing the stale Accessibility entry…"
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

cat <<EOF

✅ Done.

Next:
  1. Open the app.
  2. Grant Accessibility ONE more time (System Settings ▸ Privacy & Security ▸ Accessibility).
     If a stale "PeaceTimer" entry is still listed, select it and press "−" first.
  3. It will stop asking — the signature is now stable across rebuilds.

Re-run this script after installing a new CI build (those ship ad-hoc signed).
EOF
