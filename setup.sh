#!/bin/bash
set -e

echo "=== Discover AI Setup ==="

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "Docker required"; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "Docker Compose required"; exit 1; }

# Copy env files
if [ ! -f .env ]; then
    cp .env.example .env
    echo "Created .env from example"
fi

# Start services
echo "Starting services..."
docker-compose up --build -d

echo ""
echo "=== Setup Complete ==="
echo "Frontend: http://localhost:3000"
echo "API:      http://localhost:8000"
echo "Docs:     http://localhost:8000/docs"
echo ""
echo "Demo login:"
echo "  Email: demo@algeria.travel"
echo "  Pass:  demo1234"
