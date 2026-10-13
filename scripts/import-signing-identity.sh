#!/bin/bash
# Imports a .p12 signing identity into a throwaway keychain so codesign can use it, and prints
# the identity's SHA-1 hash (pass it to `make app SIGN_ID=...`). For CI.
#
# Usage: scripts/import-signing-identity.sh IDENTITY.p12 PASSWORD KEYCHAIN_NAME
set -euo pipefail

P12="$1"
PASSWORD="$2"
KEYCHAIN="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/$3.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"

{
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security import "$P12" -k "$KEYCHAIN" -P "$PASSWORD" -f pkcs12 -T /usr/bin/codesign
    # Lets codesign use the key without a keychain prompt, which would hang a headless runner.
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
    # codesign only looks in the search list.
    existing=()
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        existing+=("${line//\"/}")
    done < <(security list-keychains -d user)
    security list-keychains -d user -s "$KEYCHAIN" ${existing[@]+"${existing[@]}"}
} >&2

# A self-signed certificate isn't trusted, so `find-identity -v` would hide it; list them all.
HASH="$(security find-identity -p codesigning "$KEYCHAIN" | awk '$1 ~ /^[0-9]+\)$/ { print $2; exit }')"
if [ -z "$HASH" ]; then
    echo "no code-signing identity found in $P12" >&2
    exit 1
fi
echo "$HASH"
