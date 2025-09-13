#!/bin/bash
set -euo pipefail

IMAGE_NAME="cleanpdf"

# --- Build image kalau belum ada ---
if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "[INFO] Image $IMAGE_NAME belum ada, membuild dulu..."
  docker build -t "$IMAGE_NAME" .
fi

#!/bin/bash
docker run --rm -v "$(pwd):/data" cleanpdf "$@"
