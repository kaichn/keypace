#!/bin/zsh
# Creates a self-signed code-signing certificate called "KeyPace Local Signing" in your
# login Keychain. build.sh signs with it, so the app keeps the same identity across rebuilds
# and macOS doesn't ask again for Input Monitoring or Keychain access after each update.
# Optional: without it, build.sh signs ad-hoc and works the same otherwise.
set -euo pipefail
NAME="KeyPace Local Signing"

if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "\"$NAME\" already exists."; exit 0
fi

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
cat > "$W/cfg" <<CFG
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CFG

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$W/cfg" \
  -keyout "$W/key.pem" -out "$W/cert.pem" 2>/dev/null
PW="$(openssl rand -hex 16)"
# Legacy PKCS#12 encryption: the macOS Keychain can't read OpenSSL 3's default format.
openssl pkcs12 -export -legacy -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -inkey "$W/key.pem" -in "$W/cert.pem" -name "$NAME" -out "$W/id.p12" -passout "pass:$PW" 2>/dev/null \
|| openssl pkcs12 -export -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -inkey "$W/key.pem" -in "$W/cert.pem" -name "$NAME" -out "$W/id.p12" -passout "pass:$PW"
security import "$W/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$PW" -T /usr/bin/codesign
echo "Created \"$NAME\". Remove it any time in Keychain Access → login → My Certificates."
