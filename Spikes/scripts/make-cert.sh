#!/bin/bash
# Creates the spike's self-signed code-signing identity in its own keychain, so the
# login keychain is untouched and cleanup is one command (scripts/cleanup.sh).
# The certificate is not trusted by anything; codesign does not need it to be.
set -euo pipefail
NAME="Livepaper Spike Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/livepaper-spike.keychain-db"
PASS=spike # not a secret: it locks a throwaway keychain whose key is generated on this machine by this script
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "identity already exists in $KEYCHAIN"
else
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/id.p12" -passout "pass:$PASS" -name "$NAME"
  [ -f "$KEYCHAIN" ] || security create-keychain -p "$PASS" "$KEYCHAIN"
  security set-keychain-settings "$KEYCHAIN"
  security unlock-keychain -p "$PASS" "$KEYCHAIN"
  security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple: -s -k "$PASS" "$KEYCHAIN" >/dev/null
fi

# codesign only searches keychains on the user search list.
CURRENT=$(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//')
if ! grep -qF "$KEYCHAIN" <<<"$CURRENT"; then
  # shellcheck disable=SC2086
  security list-keychains -d user -s $CURRENT "$KEYCHAIN"
fi
security unlock-keychain -p "$PASS" "$KEYCHAIN"
security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME" || { echo "identity not usable"; exit 1; }
security find-certificate -c "$NAME" -Z "$KEYCHAIN" | grep "SHA-1"
