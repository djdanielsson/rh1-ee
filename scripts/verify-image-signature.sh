#!/usr/bin/env bash
# Verify a container image signature with Cosign.
set -euo pipefail

IMAGE="${1:?Image reference required}"
PUBKEY_FILE="${2:-${COSIGN_PUBKEY_FILE:-./cosign.pub}}"

if ! command -v cosign >/dev/null 2>&1; then
  echo "cosign is not installed"
  exit 1
fi

if [ ! -f "$PUBKEY_FILE" ]; then
  echo "Public key not found: $PUBKEY_FILE"
  exit 1
fi

cosign verify --key "$PUBKEY_FILE" "$IMAGE"
echo "Verified: $IMAGE"
