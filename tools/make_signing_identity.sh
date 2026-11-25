#!/usr/bin/env bash
# Creates the local self-signed code-signing identity "Perroquet" (run once); debug.sh and install.sh sign both apps with it.
#
# A stable signature keeps the macOS Accessibility grant valid across rebuilds; ad-hoc signing
# changes the code hash on every build, which silently invalidates the grant.
#
# Safe to re-run: the certificate is only created when missing, while the trust and key-access
# steps are always repeated, which repairs a half-set-up identity.
#
# The key-access step (`security set-key-partition-list`) labels its password prompt
# "(deprecated)", but it is the only way to let codesign use the key: without it, every codesign
# call of a build opens a keychain dialog, over and over.
#
# Usage: tools/make_signing_identity.sh
# Env:   KEYCHAIN=<path>  target keychain (default: login keychain)
#        SKIP_TRUST=1     do not mark the certificate as trusted
#        SKIP_KEY_ACCESS=1  do not run set-key-partition-list (both skips are for testing only)
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
NAME="$SIGNING_IDENTITY"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
OPENSSL=/usr/bin/openssl

CREATED=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
  echo "Identity \"$NAME\" already exists in $KEYCHAIN; repairing trust and key access."
  # find-certificate -c matches a substring ("Perroquet" also finds "Perroquet Dev"), so export the
  # certificate whose SHA-1 is the one of the identity named exactly "$NAME".
  SHA1="$(security find-identity -p codesigning "$KEYCHAIN" | awk -v name="\"$NAME\"" 'index($0, name) { print $2; exit }')"
  security find-certificate -a -c "$NAME" -Z -p "$KEYCHAIN" | awk -v sha="$SHA1" '
    /^SHA-1 hash:/ { keep = ($3 == sha); next }
    keep && /-----BEGIN CERTIFICATE-----/ { pem = 1 }
    pem { print }
    /-----END CERTIFICATE-----/ { pem = 0 }' > "$WORK/cert.pem"
else
  PASS="perroquet-$$"
  cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
  "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
  "$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -passout "pass:$PASS" -out "$WORK/identity.p12"
  security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
  echo "Created identity \"$NAME\" in $KEYCHAIN."
  CREATED=1
fi

if security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
  WAS_VALID=1
else
  WAS_VALID=0
fi

if [[ "${SKIP_TRUST:-}" != 1 ]]; then
  echo "macOS will now ask for your password to trust the certificate for code signing."
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"
fi

if [[ "${SKIP_KEY_ACCESS:-}" != 1 ]]; then
  echo "Enter your login keychain password so codesign can use the key without asking each time."
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$NAME" "$KEYCHAIN" >/dev/null
fi

if [[ "$CREATED" == 1 || "$WAS_VALID" == 0 ]]; then
  echo "Rebuild with ./debug.sh or ./install.sh, then remove the old Perroquet entry in"
  echo "System Settings > Privacy & Security > Accessibility and grant it again."
else
  echo "Identity \"$NAME\" repaired."
fi
