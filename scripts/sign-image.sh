#!/usr/bin/env bash
# Sign a container image with Cosign using a key-based signing key.
set -euo pipefail

IMAGE="${1:?Image reference required}"
KEY_FILE="${2:-${COSIGN_KEY_FILE:-./cosign.key}}"

if ! command -v cosign >/dev/null 2>&1; then
  echo "cosign is not installed"
  exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
  echo "Signing key not found: $KEY_FILE"
  exit 1
fi

cosign sign --key "$KEY_FILE" --yes "$IMAGE"
echo "Signed: $IMAGE"
