#!/bin/bash
# Creates the code-signing identity the nightly is signed with, and hands it to CI.
#
# macOS keys Accessibility and Microphone grants to an app's code signature. An ad-hoc
# signature changes with every build, so each nightly looked like a new app and the grants had
# to be removed and added again. Signed with the same certificate every time, the grants carry
# over. This makes a self-signed certificate for that: free, and enough for the grants. (A paid
# Developer ID would also allow notarization; until then the first launch still needs
# Open Anyway.)
#
# Run once, on your Mac, from the repo:
#     scripts/make-signing-identity.sh
# If the GitHub CLI (`gh`) is signed in, it stores the identity as the repository secrets
# MACOS_SIGNING_P12 and MACOS_SIGNING_PASSWORD. Otherwise it prints what to paste where.
# Running it again makes a new certificate, which means one more re-grant after that nightly.
#
# Options:
#   --out DIR     where to write identity.p12 and password.txt (default ~/.birdtown-flow-signing)
#   --no-upload   don't set the GitHub secrets (CI uses this to test the script)
set -euo pipefail

NAME="Birdtown Flow Signing"
REPO="futureLevi/birdtown-flow"
OUT="$HOME/.birdtown-flow-signing"
UPLOAD=1
while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --no-upload) UPLOAD=0; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

# macOS's own LibreSSL writes a .p12 that `security import` reads. OpenSSL 3 (Homebrew) needs
# -legacy for that, or the import fails with "MAC verification failed".
OPENSSL="${OPENSSL:-/usr/bin/openssl}"
LEGACY=()
if "$OPENSSL" version | grep -q '^OpenSSL 3'; then LEGACY=(-legacy); fi

mkdir -p "$OUT"
chmod 700 "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

PASSWORD="$("$OPENSSL" rand -hex 24)"
"$OPENSSL" pkcs12 -export ${LEGACY[@]+"${LEGACY[@]}"} -name "$NAME" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$OUT/identity.p12" -passout "pass:$PASSWORD"
printf '%s' "$PASSWORD" > "$OUT/password.txt"
chmod 600 "$OUT/identity.p12" "$OUT/password.txt"
echo "Made \"$NAME\" in $OUT"

[ "$UPLOAD" = 1 ] || exit 0

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    base64 < "$OUT/identity.p12" | tr -d '\n' | gh secret set MACOS_SIGNING_P12 -R "$REPO"
    gh secret set MACOS_SIGNING_PASSWORD -R "$REPO" < "$OUT/password.txt"
    echo "Stored as the secrets MACOS_SIGNING_P12 and MACOS_SIGNING_PASSWORD on $REPO."
    echo "The next nightly is signed with it. Grant Accessibility and Microphone once more after"
    echo "installing that one; later nightlies keep the grants."
else
    echo
    echo "The GitHub CLI isn't signed in, so add two secrets by hand at"
    echo "  https://github.com/$REPO/settings/secrets/actions"
    echo "  MACOS_SIGNING_P12       the output of: base64 < \"$OUT/identity.p12\" | pbcopy"
    echo "  MACOS_SIGNING_PASSWORD  the output of: pbcopy < \"$OUT/password.txt\""
fi
