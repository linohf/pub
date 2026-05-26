# AppFastAPIsimple

FastAPI application and Kubernetes HPA demo.

## Project structure

- `Dockerfile` - Python image for the FastAPI app
- `requirements.txt` - Python dependencies
- `src/app.py` - FastAPI application source
- `k8s/` - Kubernetes manifests for Deployment, Service and HPA
- `scripts/` - helper scripts to build/push/deploy
- `docs/` - documentation and usage guides

## Quick start

1. Set environment variables:

```bash
export DOCKER_USER=linohf
export CLUSTER_NAME=mi-cluster
```

2. Build and deploy:

```bash
DOCKER_USER=$DOCKER_USER TAG=1.0 ./scripts/deploy.sh
```

3. Read full usage and troubleshooting in `docs/HPA-README.md`.
