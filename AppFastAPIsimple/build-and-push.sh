#!/bin/bash

# Build and push Docker image for HPA Demo
# Usage: ./build-and-push.sh [version]
# Default version: 1.0

VERSION=${1:-1.0}
REGISTRY=${REGISTRY:-YOUR_DOCKERHUB}
IMAGE_NAME=hpa-demo
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${VERSION}"

echo "Building Docker image: $FULL_IMAGE"
docker build -t "$FULL_IMAGE" .

if [ $? -ne 0 ]; then
    echo "Error: Docker build failed"
    exit 1
fi

echo "Built successfully!"
echo ""
echo "To push to Docker Hub (if deploy script not used):"
echo "  docker push $FULL_IMAGE"
echo ""
echo "To update Kubernetes deployment, edit k8s-deployment.yaml and change:"
echo "  image: $FULL_IMAGE"
