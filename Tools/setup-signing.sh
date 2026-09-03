#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 chuahchengxi

# Creates a stable, self-signed code-signing identity named "Croissaint Utils
# Signing" in a dedicated keychain. build.sh uses it automatically, giving every
# build the same code signature — so macOS keeps granted permissions
# (Accessibility, Screen Recording) across updates instead of re-prompting.
#
# This identity name keeps its original "Croissaint Utils Signing" on purpose: it
# is the lookup key build.sh matches, and the released app's designated
# requirement is pinned to this exact certificate. Renaming it would change that
# requirement and drop every user's granted permissions. The name lives only in
# the keychain and codesign output, never in anything the app shows.
#
# Free, offline, and idempotent (re-running is a no-op once the identity exists).
# It does NOT replace Apple notarization: downloaded builds still show Gatekeeper's
# "unverified developer" prompt on first launch. It only stabilizes the identity.
#
# Maintainers: official releases use the protected release-signing environment.
# Run this only to get the same permission-preserving behavior for local builds.
set -euo pipefail

IDENTITY="Croissaint Utils Signing"
KC="$HOME/Library/Keychains/croissaint-signing.keychain-db"
KCPASS="croissaint-signing"

# Being listed is not the same as being usable. A keychain whose password no
# longer matches ours still shows its identity in find-identity, while every
# signing attempt fails with errSecInternalComponent — which is how a build
# silently falls back to ad-hoc, and how this check used to report success over
# an identity that could not sign. Unlocking is the cheap proof: it is the thing
# that was actually broken, and unlike a test signature it never waits on a GUI
# prompt, so this stays safe to run from a script or CI.
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    if security unlock-keychain -p "$KCPASS" "$KC" 2>/dev/null; then
        echo "✓ Signing identity already installed."
        exit 0
    fi
    echo "Existing '$IDENTITY' keychain does not unlock; rebuilding it."
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 3650 -nodes \
    -subj "/CN=$IDENTITY/O=Croissaint" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null
# -legacy exists only in OpenSSL 3 (Homebrew); macOS ships LibreSSL, whose
# export is already in the legacy format the keychain accepts. Passing the flag
# there fails the whole script, silently leaving builds ad-hoc signed.
LEGACY=()
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    LEGACY=(-legacy)
fi
openssl pkcs12 -export "${LEGACY[@]}" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/id.p12" -passout pass:"$KCPASS" -name "$IDENTITY"

security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$KCPASS" "$KC"
security set-keychain-settings "$KC"            # no auto-lock
security unlock-keychain -p "$KCPASS" "$KC"
security import "$WORK/id.p12" -k "$KC" -P "$KCPASS" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPASS" "$KC" >/dev/null 2>&1
EXISTING=$(security list-keychains -d user | sed 's/"//g' | xargs)
security list-keychains -d user -s "$KC" ${=EXISTING}

echo "✓ Created signing identity '$IDENTITY'. Future ./build.sh runs use it automatically."
