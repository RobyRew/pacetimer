#!/usr/bin/env bash
#
# setup-signing-secrets.sh — export your macOS codesigning identity and store it as
# the repo secrets the CI workflow expects (MACOS_CERT_P12 + MACOS_CERT_PASSWORD).
#
# WHY
#   CI signs ad-hoc by default, and an ad-hoc signature changes with every build, so
#   macOS treats each update as a brand-new app and re-asks for Accessibility. With a
#   real certificate the app gets a stable TeamIdentifier and the grant sticks.
#
# WHAT IT DOES
#   1. Exports the codesigning identity from your login keychain to a temporary .p12
#      (macOS will ask you to allow this — that approval is why it can't be automated).
#   2. Base64-encodes it and stores it as the MACOS_CERT_P12 repo secret.
#   3. Stores the randomly generated .p12 password as MACOS_CERT_PASSWORD.
#   4. Shreds the temporary file.
#
#   The private key goes straight from your keychain into your own repo's secret
#   store. It is never printed, committed, or copied anywhere else.
#
# USAGE
#   ./Scripts/setup-signing-secrets.sh [owner/repo]

set -euo pipefail

REPO="${1:-RobyRew/pacetimer}"
TMP_P12="$(mktemp -t peacetimer-cert).p12"
cleanup() { rm -f "$TMP_P12"; }
trap cleanup EXIT

command -v gh >/dev/null || { echo "❌ GitHub CLI (gh) not installed."; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "❌ Not logged in — run: gh auth login"; exit 1; }

echo "▸ Codesigning identities in your login keychain:"
security find-identity -v -p codesigning | sed 's/^/   /'
COUNT=$(security find-identity -v -p codesigning | grep -cE '^\s+[0-9]+\)' || true)
[ "$COUNT" -gt 0 ] || { echo "❌ No codesigning identity. Xcode → Settings → Accounts → add your Apple ID."; exit 1; }
if [ "$COUNT" -gt 1 ]; then
  echo "⚠️  More than one identity found — ALL of them will be exported into the .p12."
  echo "   CI picks 'Developer ID Application' first, else 'Apple Development'."
  read -r -p "   Continue? [y/N] " ok
  [ "$ok" = "y" ] || [ "$ok" = "Y" ] || { echo "Aborted."; exit 1; }
fi

# Random password — you never have to invent or remember one; it only ever has to
# match between the .p12 and the secret.
P12_PASSWORD="$(uuidgen)"

echo "▸ Exporting the identity…"
echo "  👉 macOS will now ask permission to export the private key — click Allow."
security export -t identities -f pkcs12 -P "$P12_PASSWORD" -o "$TMP_P12"
[ -s "$TMP_P12" ] || { echo "❌ Export produced nothing (was the prompt denied?)"; exit 1; }
echo "  exported ($(wc -c < "$TMP_P12" | tr -d ' ') bytes)"

echo "▸ Storing secrets on $REPO…"
base64 -i "$TMP_P12" | gh secret set MACOS_CERT_P12 -R "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set MACOS_CERT_PASSWORD -R "$REPO"

echo "▸ Secrets now on the repo:"
gh secret list -R "$REPO" | sed 's/^/   /'

cat <<EOF

✅ Done. The temporary .p12 has been deleted.

Push anything to main and the build log will show:
    Signing as: Apple Development: …
instead of:
    No MACOS_CERT_P12 secret — building ad-hoc signed (unsigned)

The shipped app will then carry a stable TeamIdentifier, so the Accessibility grant
survives updates on YOUR Mac.

Note: an "Apple Development" certificate cannot be notarised and is not valid for
distribution — other people downloading the app will still see Gatekeeper warnings.
That needs a paid "Developer ID Application" certificate.
EOF
