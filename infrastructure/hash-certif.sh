#!/usr/bin/env bash
# Terraform "external" data source program.
# Reads {"cert_pem": "..."} on stdin, prints {"hash": "..."} on stdout.
# Implements the exact method kubeadm's docs specify for
# --discovery-token-ca-cert-hash: sha256 over the DER-encoded
# SubjectPublicKeyInfo of the CA certificate's public key.
set -euo pipefail

CERT_PEM=$(jq -r '.cert_pem')

HASH=$(echo "$CERT_PEM" \
  | openssl x509 -pubkey -noout \
  | openssl asn1parse -noout -inform pem -out /dev/stdout \
  | openssl dgst -sha256 -hex \
  | sed 's/^.* //')

jq -n --arg hash "$HASH" '{"hash":$hash}'
