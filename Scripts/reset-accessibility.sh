#!/usr/bin/env bash
#
# Clears PeaceTimer's stale Accessibility (TCC) grant.
#
# Why you need this: macOS identifies an app by its *code signature*, not its name.
# Unsigned / ad-hoc-signed builds get a fresh identity on every rebuild, so the
# permission you granted five minutes ago no longer matches the binary you just
# built — the app is treated as a brand-new app and asks again, while a stale
# entry lingers in System Settings.
#
# Run this, then grant the permission once more on the new build.
# The permanent fix is to sign with a stable identity — see README "Troubleshooting".

set -euo pipefail

BUNDLE_ID="${1:-com.robyrew.peacetimer}"

echo "Resetting Accessibility permission for: $BUNDLE_ID"
tccutil reset Accessibility "$BUNDLE_ID"
echo "Done. Relaunch the app and grant Accessibility when prompted."
