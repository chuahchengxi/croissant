#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Croissaint
#
# build.sh must refuse to sign ad-hoc unless explicitly asked. A locked login
# keychain makes `security find-identity` print nothing, which looks exactly
# like a machine with no identity at all — so this stubs `security` to return
# nothing and checks both halves of the guard.
#
# Run: Tools/test-signing-guard.sh
set -uo pipefail
cd "$(dirname "$0")/.."

STUB="$(mktemp -d)"
trap 'rm -rf "$STUB"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$STUB/security"
chmod +x "$STUB/security"

fail=0
check() {  # check <name> <condition-exit-status>
    if (( $2 == 0 )); then print -r -- "ok   - $1"
    else print -r -- "FAIL - $1"; fail=1; fi
}

# 1. No identity and no flag: refuse, before building anything.
out="$(PATH="$STUB:$PATH" ./build.sh 2>&1)" && rc=0 || rc=$?
[[ $rc -ne 0 ]]; check "exits non-zero without an identity" $?
grep -q 'refusing to sign ad-hoc' <<<"$out"; check "explains the refusal" $?
grep -q 'unlock-keychain'         <<<"$out"; check "names the unlock escape hatch" $?
grep -q -- '--allow-adhoc'        <<<"$out"; check "names --allow-adhoc" $?

# 2. --allow-adhoc: the guard lets it through. The build itself is slow and is
#    not what we are testing, so give it a moment, then kill it.
log="$STUB/allow.log"
PATH="$STUB:$PATH" ./build.sh --allow-adhoc >"$log" 2>&1 & pid=$!
{ sleep 8; kill -9 $pid 2>/dev/null } & watchdog=$!
wait $pid 2>/dev/null
kill $watchdog 2>/dev/null
! grep -q 'refusing to sign ad-hoc' "$log"; check "--allow-adhoc is not refused" $?

print -r -- ""
(( fail )) && print -r -- "FAILED" || print -r -- "All checks passed."
exit $fail
