#!/usr/bin/env bash
# session-report.sh — Statusbericht für Session-Übergaben (Mensch <-> Claude Code <-> Claude Chat)
#
# Verwendung:
#   cd "/Users/koussaomar/Documents/Projet invest/Dicouver App/discover-ai-source-repo(3)"
#   bash scripts/session-report.sh
#
# Kopiere die komplette Ausgabe und füge sie am Anfang der nächsten Session ein.

set -uo pipefail

echo "======================================================"
echo " SESSION REPORT — $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================================"

echo ""
echo "--- 1. Arbeitsverzeichnis ---"
pwd

echo ""
echo "--- 2. Git: Remote & Branch ---"
git remote -v 2>/dev/null || echo "Kein Git-Remote konfiguriert"
echo "Branch: $(git branch --show-current 2>/dev/null || echo 'unbekannt')"

echo ""
echo "--- 3. Git: letzte 10 Commits ---"
git log --oneline -10 2>/dev/null || echo "Kein Git-Repository"

echo ""
echo "--- 4. Git: Arbeitsbaum-Status ---"
git status 2>/dev/null || echo "Kein Git-Repository"

echo ""
echo "--- 5. Docker: laufende Container ---"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker nicht erreichbar"

echo ""
echo "--- 6. Docker: Speicherplatz ---"
df -h / 2>/dev/null | tail -2
docker system df 2>/dev/null

echo ""
echo "--- 7. Struktur-Check: Schlüsseldateien vorhanden? ---"
for f in \
  "docker-compose.yml" \
  "docker-compose.prod.yml" \
  "docker-compose.prod.local.yml" \
  "traefik-local.yml" \
  "backend/Dockerfile" \
  "backend/app/services/llm_providers/factory.py" \
  "backend/app/services/llm_providers/openai_provider.py" \
  "backend/app/services/llm_providers/mock_provider.py" \
  "backend/app/api/v1/endpoints/reviews.py" \
  "backend/app/services/review_service.py" \
  "backend/app/services/cv_service.py" \
  "backend/app/services/constraint_solver.py" \
  "frontend/Dockerfile" \
  "frontend/next.config.mjs" \
  "frontend/eslint.config.mjs" \
  "frontend/src/proxy.ts" \
  "frontend/src/components/AppShell.tsx" \
  "frontend/tests/e2e/smoke.spec.ts" \
  "mobile/pubspec.yaml" \
  "docs/architektur.md" \
  "README.md" \
  ".github/workflows/ci.yml" \
  "deploy/k8s/README.md" \
  "CLAUDE.md"
do
  if [ -f "$f" ]; then
    echo "  OK: $f"
  else
    echo "  FEHLT: $f"
  fi
done

echo ""
echo "--- 8. .env-Dateien (nur Existenz, keine Inhalte) ---"
[ -f "backend/.env" ] && echo "  OK: backend/.env existiert" || echo "  FEHLT: backend/.env"
if [ -f "backend/.env" ]; then
  grep -q "^OPENAI_API_KEY=.\+" backend/.env 2>/dev/null \
    && echo "  OK: OPENAI_API_KEY ist gesetzt" \
    || echo "  WARNUNG: OPENAI_API_KEY ist leer -> MockProvider-Modus"
  grep "^LLM_PROVIDER=" backend/.env 2>/dev/null || echo "  WARNUNG: LLM_PROVIDER nicht gesetzt"
fi

echo ""
echo "--- 9. CLAUDE.md: Status-Tabelle ---"
if [ -f "CLAUDE.md" ]; then
  awk '/^\| Teil \| Status/,/^$/' CLAUDE.md 2>/dev/null | head -20
else
  echo "CLAUDE.md nicht gefunden"
fi

echo ""
echo "--- 10. Deployment: HTTPS-Smoke-Check (prod local) ---"
if command -v curl >/dev/null 2>&1; then
  FRONT=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 https://localhost/ 2>/dev/null || echo "000")
  echo "  Frontend https://localhost        -> HTTP $FRONT"
  HEALTH=$(curl -sk --max-time 5 https://api.localhost/health 2>/dev/null || echo "unreachable")
  echo "  API      https://api.localhost/health -> $HEALTH"
else
  echo "  curl nicht verfuegbar"
fi

echo ""
echo "--- 11. Tests: Anzahl (statisch gezaehlt) ---"
if [ -d backend/tests ]; then
  TOTAL=$(grep -rh "def test_" backend/tests --include="*.py" --exclude="conftest.py" 2>/dev/null | wc -l | tr -d ' ')
  echo "  Backend pytest-Tests: $TOTAL"
fi
[ -f frontend/playwright.config.ts ] || [ -d frontend/tests/e2e ] \
  && echo "  Playwright E2E: Suite vorhanden (13 Tests, Stand 22.08.2026)"
[ -d mobile/test ] && echo "  Flutter-Tests: $(grep -rhE 'test(Widgets)?\(' mobile/test --include="*_test.dart" 2>/dev/null | wc -l | tr -d ' ')"

echo ""
echo "--- 12. Pull Request (GitHub API) ---"
CREDS=$(printf 'protocol=https\nhost=github.com\n\n' \
  | GIT_TERMINAL_PROMPT=0 git credential fill 2>/dev/null)
TOKEN=$(printf '%s\n' "$CREDS" | grep '^password=' | cut -d= -f2-)
BRANCH=$(git branch --show-current 2>/dev/null)
if [ -n "$TOKEN" ] && [ -n "$BRANCH" ] && command -v curl >/dev/null 2>&1; then
  REPO=$(git remote get-url origin 2>/dev/null \
    | awk -F'github.com[/:]' '{print $2}' | sed 's/\.git$//')
  curl -s --max-time 8 -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/pulls?head=$(echo "$REPO" | cut -d/ -f1):$BRANCH&state=all" \
    | python3 -c "
import json,sys
try:
    prs = json.load(sys.stdin)
    if isinstance(prs, list) and prs:
        for p in prs:
            print('  PR #%s [%s] %s' % (p['number'], p['state'], p['title']))
            print('    %s' % p['html_url'])
    else:
        print('  Keine PR fuer Branch gefunden')
except Exception as e:
    print('  PR-Abfrage fehlgeschlagen:', e)
"
else
  echo "  Keine Credentials / kein curl -> PR-Status ueberspringen"
fi

echo ""
echo "======================================================"
echo " ENDE SESSION REPORT"
echo "======================================================"