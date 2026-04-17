#!/bin/sh
set -e

SESSION_FILE="/tmp/bw-session"

# Configure Vaultwarden server URL
bw config server "$BW_SERVER_URL" > /dev/null 2>&1

# Try cached session first
if [ -f "$SESSION_FILE" ]; then
  export BW_SESSION=$(cat "$SESSION_FILE")
  # Validate session is still active
  if ! bw unlock --check --session "$BW_SESSION" > /dev/null 2>&1; then
    rm -f "$SESSION_FILE"
    unset BW_SESSION
  fi
fi

# Login + unlock if no valid session
if [ ! -f "$SESSION_FILE" ]; then
  # Login via API key (reads BW_CLIENTID and BW_CLIENTSECRET from env)
  if ! bw login --check > /dev/null 2>&1; then
    bw login --apikey > /dev/null 2>&1
  fi
  # Unlock vault (reads BW_PASSWORD from env)
  export BW_SESSION=$(bw unlock --passwordenv BW_PASSWORD --raw)
  echo "$BW_SESSION" > "$SESSION_FILE"
fi

# Fetch GitHub token from Vaultwarden and configure git/gh
GITHUB_TOKEN=$(bw get password "GitHub Token" --session "$BW_SESSION" 2>/dev/null || true)
if [ -n "$GITHUB_TOKEN" ]; then
  export GITHUB_TOKEN
  # Configure git to use token for github.com HTTPS remotes
  git config --global credential.helper '!f() { echo "username=x-token"; echo "password=$GITHUB_TOKEN"; }; f'
  # Authenticate gh CLI
  echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null || true
fi

exec opencode "$@"
