#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Checks signing policy without starting a compiler or modifying a keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
printf '#!/bin/sh\nprintf called >> "$SIGNING_STUB_LOG"\nexit 0\n' > "$WORK/bin/security"
chmod +x "$WORK/bin/security"
# Execute the actual identity-resolution prefix, stopping before build steps.
sed '/^codesign_with_timestamp_retry()/,$d' build.sh > "$WORK/build.sh"
printf '\nprint -r -- "mode=$SIGN_MODE"\n' >> "$WORK/build.sh"
export SIGNING_STUB_LOG="$WORK/security.log"
export PATH="$WORK/bin:$PATH"
unset CODESIGN_IDENTITY

if output=$(zsh "$WORK/build.sh" 2>&1); then
    echo "FAIL: an identity-less build succeeded" >&2
    exit 1
fi
grep -q 'refusing to sign ad-hoc' <<< "$output"
grep -q 'unlock-keychain' <<< "$output"
grep -q -- '--allow-adhoc' <<< "$output"
for flag in --allow-adhoc --force-adhoc; do
    output=$(zsh "$WORK/build.sh" "$flag")
    grep -q 'mode=adhoc' <<< "$output"
done
printf '' > "$SIGNING_STUB_LOG"
zsh "$WORK/build.sh" --dev --force-adhoc | grep -q 'mode=adhoc'
[[ ! -s "$SIGNING_STUB_LOG" ]]

# Duplicate display names are legal; codesign needs one exact fingerprint.
printf '%s\n' '#!/bin/sh' \
    'echo '\''  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Development: Same Name"'\''' \
    'echo '\''  2) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "Apple Development: Same Name"'\''' \
    > "$WORK/bin/security"
printf '\nprint -r -- "identity=$DEVID"\n' >> "$WORK/build.sh"
output=$(zsh "$WORK/build.sh")
grep -q 'mode=devid' <<< "$output"
grep -q 'identity=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' <<< "$output"

# No secrets is an explicit ad-hoc release. Partial secrets must never be one.
unset SIGNING_CERT_P12 SIGNING_CERT_PASSWORD NOTARY_API_KEY_P8 NOTARY_KEY_ID NOTARY_ISSUER_ID REQUIRE_SIGNING
./Tools/ci-setup-signing.sh | grep -q 'No release signing credentials'
if SIGNING_CERT_P12=invalid ./Tools/ci-setup-signing.sh >/dev/null 2>&1; then
    echo 'FAIL: partial signing credentials were accepted' >&2
    exit 1
fi
if NOTARY_KEY_ID=invalid ./Tools/ci-setup-signing.sh >/dev/null 2>&1; then
    echo 'FAIL: notarization without signing credentials was accepted' >&2
    exit 1
fi
echo 'PASS: signing guards, duplicate certificate names, force-ad-hoc isolation and incomplete release credentials'
