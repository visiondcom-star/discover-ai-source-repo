#!/bin/bash
# Live RAG validation: login -> batched indexing -> semantic searches
set -e
BASE=http://localhost:8000/api/v1

TOKEN=$(curl -s -X POST "$BASE/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@algeria.travel","password":"admin1234"}' \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')
echo "login OK, token length: ${#TOKEN}"

echo "--- INDEX (batched OpenAI embeddings) ---"
curl -s -X POST "$BASE/rag/index" \
  -H "Authorization: Bearer $TOKEN" -H "X-Tenant-Slug: algeria"
echo

echo "--- SEARCH 1: ruines romaines au bord de la mer ---"
curl -s -X POST "$BASE/rag/search" \
  -H "Authorization: Bearer $TOKEN" -H "X-Tenant-Slug: algeria" \
  -H 'Content-Type: application/json' \
  -d '{"query":"je veux visiter des ruines romaines au bord de la mer","top_k":3}' \
| python3 -c 'import sys,json
for r in json.load(sys.stdin)["results"]:
    s, n, c = r["score"], r["name"], r["city"]
    print("%.4f  %s (%s)" % (s, n, c))'

echo "--- SEARCH 2: désert et gravures rupestres ---"
curl -s -X POST "$BASE/rag/search" \
  -H "Authorization: Bearer $TOKEN" -H "X-Tenant-Slug: algeria" \
  -H 'Content-Type: application/json' \
  -d '{"query":"trekking dans le desert avec gravures rupestres anciennes","top_k":3}' \
| python3 -c 'import sys,json
for r in json.load(sys.stdin)["results"]:
    s, n, c = r["score"], r["name"], r["city"]
    print("%.4f  %s (%s)" % (s, n, c))'
