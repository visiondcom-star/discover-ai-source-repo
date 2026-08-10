.PHONY: dev build test backend frontend mobile clean

# Development
dev:
	docker-compose up --build

# Testing
test:
	cd backend && pytest tests/ -v --cov=app
	cd mobile && flutter test --coverage

# Backend only
backend:
	cd backend && uvicorn app.main:app --reload

# Frontend only
frontend:
	cd frontend && npm run dev

# Mobile
mobile:
	cd mobile && flutter run

# Build production images
build:
	docker-compose -f docker-compose.prod.yml build

# Deploy to K8s
deploy-k8s:
	kubectl apply -f deploy/k8s/

# Clean
clean:
	docker-compose down -v
	docker system prune -f
