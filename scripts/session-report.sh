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
  "backend/Dockerfile" \
  "backend/app/services/llm_providers/factory.py" \
  "backend/app/services/llm_providers/openai_provider.py" \
  "backend/app/services/llm_providers/mock_provider.py" \
  "frontend/Dockerfile" \
  "frontend/next.config.js" \
  "frontend/src/components/AppShell.tsx" \
  "frontend/tests/e2e/smoke.spec.ts" \
  "mobile/pubspec.yaml" \
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
echo "======================================================"
echo " ENDE SESSION REPORT"
echo "======================================================"