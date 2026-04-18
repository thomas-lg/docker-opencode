#!/bin/sh

SESSION_FILE="/tmp/bw-session"
LOG="[opencode]"

log()  { echo "$LOG $*"; }
warn() { echo "$LOG WARNING: $*"; }

# ── Vaultwarden server ────────────────────────────────────────────────────────

if [ -z "$BW_SERVER_URL" ]; then
  warn "BW_SERVER_URL is not set, skipping Vaultwarden configuration."
else
  log "Configuring Vaultwarden server: $BW_SERVER_URL"
  bw config server "$BW_SERVER_URL" > /dev/null 2>&1 || warn "bw config server failed."
fi

# ── Session restore ───────────────────────────────────────────────────────────

if [ -f "$SESSION_FILE" ]; then
  log "Restoring cached Vaultwarden session..."
  export BW_SESSION=$(cat "$SESSION_FILE")
  if ! bw unlock --check --session "$BW_SESSION" > /dev/null 2>&1; then
    log "Cached session expired or invalid, discarding."
    rm -f "$SESSION_FILE"
    unset BW_SESSION
  else
    log "Cached session is valid."
  fi
fi

# ── Login + unlock (with retry) ───────────────────────────────────────────────

if [ ! -f "$SESSION_FILE" ]; then
  log "No valid session found, logging in..."
  if ! bw login --check > /dev/null 2>&1; then
    log "Authenticating with API key..."
    if ! bw login --apikey > /dev/null 2>&1; then
      warn "bw login failed. Check BW_CLIENTID and BW_CLIENTSECRET."
      warn "Starting OpenCode without Vaultwarden access."
      log "Starting OpenCode..."
      exec opencode "$@"
    fi
    log "Login successful."
  else
    log "Already logged in."
  fi

  ATTEMPT=0
  MAX_ATTEMPTS=3
  RETRY_DELAY=5

  while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    log "Unlocking vault... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null || true)
    if [ -n "$BW_SESSION" ]; then
      export BW_SESSION
      echo "$BW_SESSION" > "$SESSION_FILE"
      log "Vault unlocked successfully."
      break
    fi
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
      warn "Unlock failed, retrying in ${RETRY_DELAY}s..."
      sleep $RETRY_DELAY
    fi
  done

  if [ -z "$BW_SESSION" ]; then
    warn "Vault unlock failed after $MAX_ATTEMPTS attempts. Starting degraded (no secrets available)."
    log "Starting OpenCode..."
    exec opencode "$@"
  fi
fi

# ── GitHub token ──────────────────────────────────────────────────────────────

log "Fetching GitHub token from Vaultwarden..."
GITHUB_TOKEN=$(bw get password "github_token" --session "$BW_SESSION" 2>/dev/null || true)

if [ -n "$GITHUB_TOKEN" ]; then
  log "GitHub token fetched, configuring git and gh CLI..."
  # Store token persistently for gh — works in all docker exec shells without env vars
  echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null \
    && log "gh CLI authenticated." \
    || warn "gh auth login failed."
  # Configure git credential helper
  cat > /usr/local/bin/git-credential-vaultwarden <<EOF
#!/bin/sh
echo "username=x-token"
echo "password=$GITHUB_TOKEN"
EOF
  chmod +x /usr/local/bin/git-credential-vaultwarden
  git config --global credential.https://github.com.helper vaultwarden
  log "git configured."
else
  warn "GitHub token not found in vault. git push and gh will not be authenticated."
fi

# ── Start ─────────────────────────────────────────────────────────────────────

log "Starting OpenCode..."
exec opencode "$@"
