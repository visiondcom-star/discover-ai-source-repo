-- Auto-create the test database used by the backend pytest suite.
-- Runs on first container initialization (docker-entrypoint-initdb.d).
CREATE DATABASE discoverai_test;
