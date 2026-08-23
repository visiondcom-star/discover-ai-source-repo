-- Proves the vector pipeline end-to-end at SQL level:
-- 1. inject a deterministic 1536-dim vector on one POI
-- 2. run a cosine KNN query and show the planner uses the HNSW index
-- 3. clean up
\set ON_ERROR_STOP on

UPDATE pois
SET embedding = (
  SELECT ('[' || array_to_string(array_agg(((n % 100) * 0.01)::text), ',') || ']')::vector
  FROM generate_series(1, 1536) AS n
)
WHERE slug = 'casbah-dalger';

SET enable_seqscan = off;

EXPLAIN ANALYZE
SELECT name
FROM pois
WHERE tenant_id = (SELECT id FROM tenants WHERE slug = 'algeria')
ORDER BY embedding <=> (
  SELECT ('[' || array_to_string(array_agg(((n % 100) * 0.01)::text), ',') || ']')::vector
  FROM generate_series(1, 1536) AS n
)
LIMIT 3;

UPDATE pois SET embedding = NULL WHERE slug = 'casbah-dalger';
