#!/bin/sh
# Refresh scripts/ca-certificates.crt from curl.se's Mozilla root-store
# mirror (https://curl.se/docs/caextract.html). Run on a normal machine
# with a working trust store, not on the JetKVM device - see
# docs/jetkvm-behavior.md#no-ca-trust-store for why.
#
#   sh scripts/refresh-ca-bundle.sh
#
# Review the diff before committing.

set -e

cd "$(dirname "$0")"

TMP="$(mktemp)"
curl -fsSL -o "$TMP" https://curl.se/ca/cacert.pem

EXPECTED="$(curl -fsSL https://curl.se/ca/cacert.pem.sha256 | awk '{print $1}')"
ACTUAL="$(sha256sum "$TMP" | awk '{print $1}')"

if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "Checksum mismatch: expected $EXPECTED, got $ACTUAL" >&2
  rm -f "$TMP"
  exit 1
fi

mv "$TMP" ca-certificates.crt
echo "Updated ca-certificates.crt (sha256: $ACTUAL)"
head -5 ca-certificates.crt
