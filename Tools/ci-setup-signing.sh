#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 chuahchengxi

# Imports the stable signing certificate into a keychain on CI so build.sh signs
# releases with the same identity used locally. This keeps the bundle's
# designated requirement constant, so users keep their granted permissions
# across updates. No-op (and ad-hoc build) only when no credentials are configured.
set -euo pipefail
umask 077

if [[ -z "${SIGNING_CERT_P12:-}" || -z "${SIGNING_CERT_PASSWORD:-}" ]]; then
    if [[ "${REQUIRE_SIGNING:-0}" == "1" || -n "${SIGNING_CERT_P12:-}${SIGNING_CERT_PASSWORD:-}${NOTARY_API_KEY_P8:-}${NOTARY_KEY_ID:-}${NOTARY_ISSUER_ID:-}" ]]; then
        echo "Release signing credentials are incomplete." >&2
        exit 1
    fi
    echo "No release signing credentials — building ad-hoc."
    exit 0
fi

if [[ -n "${NOTARY_API_KEY_P8:-}${NOTARY_KEY_ID:-}${NOTARY_ISSUER_ID:-}" ]] \
    && [[ -z "${NOTARY_API_KEY_P8:-}" || -z "${NOTARY_KEY_ID:-}" || -z "${NOTARY_ISSUER_ID:-}" ]]; then
    echo "Release notarization credentials are incomplete." >&2
    exit 1
fi

TMP="${RUNNER_TEMP:-/tmp}"
KCPASS="ci-signing"
KC="$TMP/croissaint-signing.keychain-db"
P12="$TMP/croissaint-signing.p12"
trap 'rm -f "$P12"' EXIT

printf '%s' "$SIGNING_CERT_P12" | base64 --decode > "$P12"
security create-keychain -p "$KCPASS" "$KC"
security set-keychain-settings "$KC"
security unlock-keychain -p "$KCPASS" "$KC"
security import "$P12" -k "$KC" -P "${SIGNING_CERT_PASSWORD:-}" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KC" >/dev/null 2>&1
EXISTING=$(security list-keychains -d user | sed 's/"//g' | xargs)
security list-keychains -d user -s "$KC" ${=EXISTING}
rm -f "$P12"
# Select only the imported keychain, not an unrelated identity on the runner.
# Self-signed certificates stay on build.sh's legacy path (no hardened runtime).
DEVID=$(security find-identity -v -p codesigning "$KC" \
    | sed -nE '/"Developer ID Application:/s/.* ([A-Fa-f0-9]{40}) .*/\1/p' | head -1)
if [[ -n "$DEVID" ]]; then
    [[ -n "${GITHUB_ENV:-}" ]] && echo "CODESIGN_IDENTITY=$DEVID" >> "$GITHUB_ENV"
elif [[ -n "${NOTARY_API_KEY_P8:-}" ]]; then
    echo "Notarization requires a valid Developer ID Application certificate." >&2
    exit 1
elif ! security find-identity -p codesigning "$KC" | grep -q '"Croissaint Utils Signing"'; then
    echo "Release certificate must be Developer ID Application or Croissaint Utils Signing." >&2
    exit 1
fi
echo "Signing certificate imported."
