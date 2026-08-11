FROM pgvector/pgvector:pg16

# Create the test database used by the backend pytest suite
# on first container initialization.
COPY init-test-db.sql /docker-entrypoint-initdb.d/init-test-db.sql
