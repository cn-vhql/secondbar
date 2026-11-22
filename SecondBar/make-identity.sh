#!/bin/bash
# Creates a self-signed code-signing identity in the login keychain, once.
#
# Why: TCC (the Accessibility permission) remembers an app by its signing
# identity. An ad-hoc signature has no identity, so every rebuild looks like a
# brand new app and the permission has to be granted again. A stable self-signed
# certificate makes the grant survive rebuilds.
set -euo pipefail

NAME="SecondBar Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "identity '$NAME' already exists"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/cert.cnf" <<'CONF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = SecondBar Dev
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$work/key.pem" -out "$work/cert.pem" -config "$work/cert.cnf" >/dev/null 2>&1

openssl pkcs12 -export -out "$work/id.p12" \
  -inkey "$work/key.pem" -in "$work/cert.pem" -passout pass:secondbar \
  -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES >/dev/null 2>&1

# security(1) rejects an empty password, so the p12 carries a throwaway one.
security import "$work/id.p12" -k "$KEYCHAIN" -P secondbar -T /usr/bin/codesign >/dev/null
# Let codesign use the key without a prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "created identity '$NAME'"
security find-identity -v -p codesigning "$KEYCHAIN" | tail -3
