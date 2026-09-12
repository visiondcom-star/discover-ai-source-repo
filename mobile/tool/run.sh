#!/usr/bin/env bash
# Convenience wrapper for `flutter run` on iOS Simulator.
#
# Usage:
#   tool/run.sh [API_BASE_URL] [TENANT_SLUG] [DEVICE]
#
# Examples:
#   tool/run.sh                                    # algeria / localhost:8000 / iPhone 15
#   tool/run.sh http://10.0.2.2:8000/api/v1        # Android emulator instead of iOS
#   tool/run.sh http://localhost:8000/api/v1 france "iPhone 15 Pro"
#
set -euo pipefail

API_BASE_URL="${1:-http://localhost:8000/api/v1}"
TENANT_SLUG="${2:-algeria}"
DEVICE="${3:-iPhone 15}"

cd "$(dirname "$0")/.." # → mobile/

echo ">>> flutter run"
echo "    device:        $DEVICE"
echo "    API_BASE_URL:  $API_BASE_URL"
echo "    TENANT_SLUG:   $TENANT_SLUG"
echo "    DEMO_EMAIL:    demo@${TENANT_SLUG}.travel"
echo ""

exec flutter run -d "$DEVICE" \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=TENANT_SLUG="$TENANT_SLUG" \
  --dart-define=DEMO_EMAIL="demo@${TENANT_SLUG}.travel"
