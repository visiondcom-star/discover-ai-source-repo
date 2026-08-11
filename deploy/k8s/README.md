# Kubernetes Deployment Guide

## Overview

This directory contains Kubernetes manifests for deploying the Discover AI platform using Kustomize for environment management.

## Architecture

The deployment consists of:
- **Namespace:** `discover-ai`
- **Backend:** FastAPI application (2-3 replicas, autoscaling 2-6)
- **Frontend:** Next.js application (2 replicas)
- **Database:** PostgreSQL 16 with persistent storage (10Gi)
- **Cache:** Redis 7
- **Ingress:** NGINX Ingress Controller with Let's Encrypt TLS
- **Autoscaling:** HPA for both backend and frontend

## Prerequisites

### 1. Kubernetes Cluster
- Kubernetes 1.24+
- NGINX Ingress Controller installed
- cert-manager installed (for Let's Encrypt)
- kubectl configured to access your cluster

### 2. Docker Images
Build and push the Docker images to a registry before deployment.

### 3. Update Image References
Update the image names in deployment manifests to match your registry.

## Deployment

### Staging Environment
```bash
kubectl apply -k overlays/staging
```

### Production Environment
```bash
kubectl apply -k overlays/production
```

## Configuration

Update `secrets.yaml` with your actual values before deploying to production.

## Verification

After deployment, verify:
```bash
kubectl get pods -n discover-ai
kubectl get services -n discover-ai
kubectl get ingress -n discover-ai
```

## Next Steps

1. Set up a Kubernetes cluster
2. Install NGINX Ingress Controller
3. Install cert-manager for TLS
4. Build and push Docker images
5. Update secrets with production values
6. Configure DNS for your domain
7. Deploy staging environment
8. Test thoroughly
9. Deploy to production

See inline comments in manifest files for detailed configuration options.