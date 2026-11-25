#!/usr/bin/env bash
set -euo pipefail

# Create a self-signed code-signing certificate in the login keychain (once per Mac).
#
# Why: macOS ties the Accessibility grant to the app's code signature. An ad-hoc signature
# is just a hash of that one build, so every rebuild looks like a different app: System
# Settings still shows the toggle on, but the new build is refused. Signing every build with
# the same certificate makes the grant survive rebuilds.
#
# The certificate is local to this Mac, valid for 10 years and trusted by nobody else; it is
# not a substitute for Developer ID when shipping to other people (see notarize.sh).
#
#   ./scripts/setup-signing.sh          # no-op when the certificate already exists
#
# To remove it: Keychain Access ▸ login ▸ My Certificates ▸ delete "Local Code Signing".

NAME="${LOCAL_SIGN_NAME:-Local Code Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Signing certificate \"$NAME\" already exists."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/cert.conf" <<EOF
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
EOF

# /usr/bin/openssl (LibreSSL) writes a PKCS#12 that `security import` can read.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.conf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/identity.p12" -passout pass:local

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P local -T /usr/bin/codesign >/dev/null

echo "Created signing certificate \"$NAME\" in the login keychain."
echo "The first build may ask for your login password: choose \"Always Allow\"."
