#!/usr/bin/env bash
# Simple deploy script: build, push, and deploy to Kubernetes
# Usage: DOCKER_USER=myuser TAG=1.0 ./deploy.sh

set -euo pipefail

DOCKER_USER=${DOCKER_USER:-}
TAG=${TAG:-1.0}

if [ -z "$DOCKER_USER" ]; then
  echo "Set DOCKER_USER environment variable, e.g. DOCKER_USER=youruser"
  exit 1
fi

IMAGE="$DOCKER_USER/hpa-demo:$TAG"

echo "Building $IMAGE"
docker build -t "$IMAGE" .

echo "Pushing $IMAGE"
docker push "$IMAGE"

echo "Applying manifests (deployment will be updated to use image)
If deployment doesn't exist, apply manifests first with: kubectl apply -f k8s-deployment.yaml -f k8s-service.yaml -f k8s-hpa.yaml"

# Ensure manifests exist
kubectl apply -f k8s-deployment.yaml -f k8s-service.yaml -f k8s-hpa.yaml || true

echo "Setting deployment image to $IMAGE"
kubectl set image deployment/hpa-demo app="$IMAGE" --record

echo "Waiting for rollout to complete"
kubectl rollout status deployment/hpa-demo

echo "Done. To access locally: kubectl port-forward svc/hpa-demo 8000:8000"
