#!/bin/bash
# Runs once at container start to initialize the openQA database,
# generate an API key, and load the Rocky distri templates.
set -euo pipefail

LOG=/var/log/openqa/bootstrap.log
mkdir -p /var/log/openqa

# Ensure volume-mounted directories have correct ownership (uid may differ
# between image rebuilds if the named volume was initialised by an older image)
chown -R geekotest:geekotest /var/lib/openqa/testresults /var/lib/openqa/factory/iso 2>/dev/null || true

echo "[bootstrap] waiting for postgresql..." | tee -a "$LOG"
for i in $(seq 1 30); do
    pg_isready -q && break
    sleep 2
done

echo "[bootstrap] creating openQA database..." | tee -a "$LOG"
# Create PostgreSQL user and database if they don't exist
su - postgres -c "psql -c \"SELECT 1 FROM pg_roles WHERE rolname='geekotest'\" | grep -q 1" 2>/dev/null || \
    su - postgres -c "createuser geekotest" 2>>"$LOG"
su - postgres -c "psql -lqt | cut -d \| -f 1 | grep -qw openqa" 2>/dev/null || \
    su - postgres -c "createdb -O geekotest openqa" 2>>"$LOG"
echo "[bootstrap] database ready" | tee -a "$LOG"

# Wait for webui to start and initialize schema
echo "[bootstrap] waiting for webui to initialize..." | tee -a "$LOG"
for i in $(seq 1 60); do
    curl -sf http://localhost/api/v1/workers > /dev/null 2>&1 && break
    sleep 2
done

# ── seed API key (idempotent) ─────────────────────────────────────────────────
KEYFILE=/etc/openqa/client.conf.d/localhost.conf
if ! grep -q '^\[localhost\]' "$KEYFILE" 2>/dev/null; then
    echo "[bootstrap] generating API key..." | tee -a "$LOG"

    # Generate proper 16-digit hex keys
    KEY=$(head -c 8 /dev/urandom | od -A n -t x1 | tr -d ' \n')
    SECRET=$(head -c 8 /dev/urandom | od -A n -t x1 | tr -d ' \n')

    cat > "$KEYFILE" <<EOF
[localhost]
key = $KEY
secret = $SECRET

[http://localhost]
key = $KEY
secret = $SECRET
EOF
    chmod 644 "$KEYFILE"
    echo "[bootstrap] wrote $KEYFILE" | tee -a "$LOG"

    # Insert keys into database
    echo "[bootstrap] inserting API keys into database..." | tee -a "$LOG"
    su - postgres -c "psql openqa" <<EOSQL 2>>"$LOG"
-- Create admin user if doesn't exist (provider must be specified for unique constraint)
INSERT INTO users (username, provider, email, fullname, is_admin, t_created, t_updated)
VALUES ('admin', '', 'admin@localhost', 'Admin User', 1, NOW(), NOW())
ON CONFLICT (username, provider) DO UPDATE SET is_admin = 1;

-- Insert API key (delete old keys for this user first since there's no unique constraint on key)
DELETE FROM api_keys WHERE user_id IN (SELECT id FROM users WHERE username = 'admin' AND provider = '');
INSERT INTO api_keys (key, secret, user_id, t_created, t_updated)
SELECT '$KEY', '$SECRET', id, NOW(), NOW()
FROM users WHERE username = 'admin' AND provider = '';
EOSQL
    echo "[bootstrap] API keys configured" | tee -a "$LOG"
fi

# ── load Rocky templates ──────────────────────────────────────────────────────
TESTS=/var/lib/openqa/share/tests/rocky
if [ -f "$TESTS/fifloader.py" ]; then
    echo "[bootstrap] loading Rocky templates..." | tee -a "$LOG"
    cd "$TESTS"
    sudo -u geekotest python3 fifloader.py -l -c templates.fif.json \
        2>>"$LOG" && echo "[bootstrap] templates loaded." | tee -a "$LOG" \
        || echo "[bootstrap] WARNING: template load failed (may need manual run)" | tee -a "$LOG"
fi

echo "[bootstrap] done." | tee -a "$LOG"
