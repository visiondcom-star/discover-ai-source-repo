#!/usr/bin/env bash
# Runs the isolated chat E2E (integration_test/chat_e2e.dart) on Chrome via
# the official web procedure: flutter drive -d web-server + chromedriver:4444.
#
# Usage: tool/run_chat_e2e.sh [API_BASE_URL] [TENANT_SLUG]
#
# Notes:
# - chromedriver must EXACTLY match the local Chrome build (major.minor.build).
#   Adjust CD_VERSION below if Chrome is updated.
# - The screenshot of the rendered reply is written to
#   test_driver/chat_reply.png by the extended driver.
set -euo pipefail

API_BASE_URL="${1:-http://localhost:8000/api/v1}"
TENANT_SLUG="${2:-algeria}"
CD_VERSION="151.0.7922.138" # keep in sync with local Chrome (see chrome --version)
CD_DIR="/tmp/cd${CD_VERSION}"
CD_BIN="$CD_DIR/chromedriver-mac-arm64/chromedriver"

cd "$(dirname "$0")/.." # mobile/

# 0) Backend must be reachable.
if ! curl -sf -o /dev/null "$API_BASE_URL/pois/"; then
  echo "ERROR: backend unreachable at $API_BASE_URL" >&2
  exit 1
fi
echo "backend OK: $API_BASE_URL"

# 1) Ensure a matching chromedriver (mac-arm64) is available.
if [[ ! -x "$CD_BIN" ]]; then
  echo "Downloading chromedriver $CD_VERSION (mac-arm64)..."
  mkdir -p "$CD_DIR"
  curl -sL -o "$CD_DIR/cd.zip" \
    "https://storage.googleapis.com/chrome-for-testing-public/$CD_VERSION/mac-arm64/chromedriver-mac-arm64.zip"
  unzip -o -q "$CD_DIR/cd.zip" -d "$CD_DIR"
fi

# 2) Start chromedriver on :4444 (quote the '*', otherwise zsh globs it!).
pkill -9 chromedriver 2>/dev/null || true
"$CD_BIN" --port=4444 --allowed-origins='*' > /tmp/chromedriver_e2e.log 2>&1 &
CD_PID=$!
trap 'kill -9 "$CD_PID" 2>/dev/null || true' EXIT
for _ in {1..20}; do
  if curl -sf -o /dev/null http://localhost:4444/status; then
    break
  fi
  sleep 0.5
done
if ! curl -sf -o /dev/null http://localhost:4444/status; then
  echo "ERROR: chromedriver failed to start (see /tmp/chromedriver_e2e.log)" >&2
  exit 1
fi
echo "chromedriver ready on :4444"

# 3) Run the test.
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/chat_e2e.dart \
  -d web-server \
  --web-port 58030 \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=TENANT_SLUG="$TENANT_SLUG"
