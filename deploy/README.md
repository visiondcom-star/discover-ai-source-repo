# Deployment Guide

This folder contains Kubernetes manifests for production deployment of the Discover AI platform.

## Included manifests

- `k8s/namespace.yaml` – Namespace definition for `discover-ai`
- `k8s/secrets.yaml` – Opaque secret for database credentials, app secret, and API keys
- `k8s/postgres.yaml` – PostgreSQL deployment, service, and PVC
- `k8s/redis.yaml` – Redis deployment and service
- `k8s/backend.yaml` – Backend deployment and service
- `k8s/frontend.yaml` – Frontend deployment and service
- `k8s/ingress.yaml` – Ingress configuration for frontend and backend domains
- `k8s/backend-hpa.yaml` – HorizontalPodAutoscaler for the backend
- `k8s/frontend-hpa.yaml` – HorizontalPodAutoscaler for the frontend

## Deploying

Before applying the manifests, update `k8s/secrets.yaml` with real values and configure the domains in `k8s/ingress.yaml`.

Apply everything with:

```bash
kubectl apply -f deploy/k8s/namespace.yaml
kubectl apply -f deploy/k8s/secrets.yaml
kubectl apply -f deploy/k8s/postgres.yaml
kubectl apply -f deploy/k8s/redis.yaml
kubectl apply -f deploy/k8s/backend.yaml
kubectl apply -f deploy/k8s/frontend.yaml
kubectl apply -f deploy/k8s/ingress.yaml
kubectl apply -f deploy/k8s/backend-hpa.yaml
kubectl apply -f deploy/k8s/frontend-hpa.yaml
```

If you manage the cluster with a single command, use:

```bash
kubectl apply -f deploy/k8s
```

Or with Kustomize support:

```bash
kubectl apply -k deploy/k8s
```

For environment-specific overlays, use:

```bash
kubectl apply -k deploy/k8s/overlays/staging
```

```bash
kubectl apply -k deploy/k8s/overlays/production
```

## Notes

- `ingress.yaml` assumes an NGINX ingress controller and cert-manager for TLS.
- `frontend.yaml` currently uses `NEXT_PUBLIC_API_URL` to point to the backend API.
- `backend.yaml` reads sensitive values from the `discover-ai-secrets` secret.
