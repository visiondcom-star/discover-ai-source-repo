-- Auto-create the test database used by the backend pytest suite.
-- Runs on first container initialization (docker-entrypoint-initdb.d).
CREATE DATABASE discoverai_test;

-- Activate the pgvector extension on the dev database.
-- During init the default connection is the dev DB (POSTGRES_DB: destinos_dev),
-- so CREATE EXTENSION here applies to destinos_dev before switching databases.
CREATE EXTENSION IF NOT EXISTS vector;

-- `\c discoverai_test` switches the psql connection to the test database,
-- otherwise the extension would be created on the default (destinos_dev) only.
\c discoverai_test
CREATE EXTENSION IF NOT EXISTS vector;

