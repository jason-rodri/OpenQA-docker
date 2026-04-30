#!/bin/bash
# Wrapper script for openQA worker to ensure services are ready
set -euo pipefail

INSTANCE=${1:-1}
LOG=/var/log/openqa/worker-${INSTANCE}-startup.log

echo "[worker-${INSTANCE}] waiting for API to be accessible..." | tee -a "$LOG"
for i in $(seq 1 30); do
    if curl -sf http://localhost/api/v1/workers > /dev/null 2>&1; then
        echo "[worker-${INSTANCE}] API is ready" | tee -a "$LOG"
        break
    fi
    sleep 2
done

echo "[worker-${INSTANCE}] checking API authentication..." | tee -a "$LOG"
if openqa-cli api workers 2>&1 | grep -q "workers"; then
    echo "[worker-${INSTANCE}] authentication successful" | tee -a "$LOG"
else
    echo "[worker-${INSTANCE}] WARNING: authentication check failed, proceeding anyway" | tee -a "$LOG"
fi

# Clean up any stale lock files
POOL_DIR="/var/lib/openqa/pool/${INSTANCE}"
if [ -f "${POOL_DIR}/.locked" ]; then
    echo "[worker-${INSTANCE}] removing stale lock file" | tee -a "$LOG"
    rm -f "${POOL_DIR}/.locked"
fi

echo "[worker-${INSTANCE}] starting worker..." | tee -a "$LOG"
exec /usr/share/openqa/script/worker --instance "$INSTANCE"
