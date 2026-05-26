# FastAPI HPA Demo

Simple FastAPI application for testing Horizontal Pod Autoscaler (HPA) based on CPU usage.

## Endpoints

- `GET /` - Health check with API info
- `GET /health` - Liveness/readiness probe
- `GET /cpu?duration=1&intensity=1` - CPU stress endpoint
- `GET /metrics` - Prometheus metrics

## CPU Stress Endpoint

The `/cpu` endpoint allows you to simulate CPU-intensive workload:

```bash
# Default: 1 second of CPU stress with intensity 1
curl http://localhost:8000/cpu

# 5 seconds with intensity 2 (2 parallel CPU tasks)
curl http://localhost:8000/cpu?duration=5&intensity=2

# 10 seconds with intensity 4 (4 parallel CPU tasks)
curl http://localhost:8000/cpu?duration=10&intensity=4
```

## Local Testing

### Build and Run

Use your Docker Hub username in place of YOUR_DOCKERHUB below. You can use the included `deploy.sh` script.

```bash
# Build, push and deploy (example)
DOCKER_USER=YOUR_DOCKERHUB TAG=1.0 ./deploy.sh

# Or build and run locally
docker build -t YOUR_DOCKERHUB/hpa-demo:1.0 .
docker run -p 8000:8000 YOUR_DOCKERHUB/hpa-demo:1.0
```

### Load Testing

```bash
# Install Apache Bench (ab)
# On Ubuntu: sudo apt-get install apache2-utils
# On macOS: brew install httpd

# Simple load test
ab -n 1000 -c 10 http://localhost:8000/cpu?duration=5&intensity=2

# Continuous load test
while true; do curl http://localhost:8000/cpu?duration=5&intensity=2; done
```

## Kubernetes Deployment

### Prerequisites

- Kubernetes cluster with `metrics-server` installed
- Docker image pushed to registry (YOUR_DOCKERHUB/hpa-demo:1.0)

### Deploy (simple, portable)

```bash
# Use deploy script which builds, pushes and updates the deployment image
DOCKER_USER=YOUR_DOCKERHUB TAG=1.0 ./deploy.sh

# Or manually apply manifests once and then update image
kubectl apply -f k8s-deployment.yaml -f k8s-service.yaml -f k8s-hpa.yaml
kubectl set image deployment/hpa-demo app=YOUR_DOCKERHUB/hpa-demo:1.0

# Check deployment
kubectl get deployments
kubectl get pods
kubectl get svc hpa-demo

# Monitor HPA
kubectl get hpa hpa-demo --watch
kubectl describe hpa hpa-demo
```

---

**Pasos detallados por entorno**

**ANTES DE EMPEZAR: Setea tus variables de entorno para que los comandos sean copy-paste:**

```bash
# En bash/WSL
export DOCKER_USER=linohf
export CLUSTER_NAME=mi-cluster
```

```powershell
# En PowerShell (Windows)
$env:DOCKER_USER="linohf"
$env:CLUSTER_NAME="mi-cluster"
```

Luego los ejemplos debajo usarán `$DOCKER_USER` y `$CLUSTER_NAME` automáticamente.

### k3d (local)

1. Asegura que tienes un cluster k3d en marcha:

```bash
k3d cluster list
# si no existe, crea uno
k3d cluster create $CLUSTER_NAME
```

2. Instala `metrics-server` si no está:

```bash
# En bash/WSL
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system patch deployment metrics-server --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' 2>/dev/null || true

# En PowerShell (Windows)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system patch deployment metrics-server --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args","value":["--kubelet-insecure-tls"]}]' 2>$null

# Verifica que está corriendo
kubectl get deployment metrics-server -n kube-system
```

3. Opciones para la imagen:

- Importar la imagen localmente (rápido, no requiere push):

```bash
# Desde AppFastAPIsimple
docker build -t $DOCKER_USER/hpa-demo:1.0 .
k3d image import --cluster $CLUSTER_NAME $DOCKER_USER/hpa-demo:1.0
kubectl apply -f k8s-deployment.yaml -f k8s-service.yaml -f k8s-hpa.yaml
kubectl set image deployment/hpa-demo app=$DOCKER_USER/hpa-demo:1.0
kubectl rollout status deployment/hpa-demo
```

- O usar Docker Hub (útil para replicar en la nube):

```bash
TAG=1.0 ./deploy.sh
```

4. Probar y generar carga:

```bash
kubectl port-forward svc/hpa-demo 8000:8000 &
curl http://localhost:8000/cpu?duration=5&intensity=2
# o desde dentro del cluster
kubectl run -it --rm loadgen --image=curlimages/curl --restart=Never -- \
  sh -c 'for i in {1..100}; do curl -s http://hpa-demo:8000/cpu?duration=3&intensity=2 >/dev/null; done'
kubectl get hpa hpa-demo --watch
```

### GKE (Google Kubernetes Engine)

1. Crea un cluster GKE o usa uno existente. Habilita la API si hace falta:

```bash
gcloud config set project YOUR_PROJECT_ID
gcloud container clusters create demo-cluster --num-nodes=2 --region=us-central1
gcloud container clusters get-credentials demo-cluster --region=us-central1
```

2. Asegura que `metrics-server` o las métricas integradas están disponibles (GKE suele proveer métricas). Si usas GKE Autopilot o versiones recientes, HPA funciona con métricas habilitadas.

3. Construye y sube la imagen a Google Container Registry (o usa Docker Hub):

```bash
# Opción A: Usando GCR
gcloud auth configure-docker
docker build -t gcr.io/YOUR_PROJECT_ID/hpa-demo:1.0 .
docker push gcr.io/YOUR_PROJECT_ID/hpa-demo:1.0
kubectl apply -f k8s-deployment.yaml -f k8s-service.yaml -f k8s-hpa.yaml
kubectl set image deployment/hpa-demo app=gcr.io/YOUR_PROJECT_ID/hpa-demo:1.0
kubectl rollout status deployment/hpa-demo
```

```bash
# Opción B: Usando Docker Hub (copy-paste con $DOCKER_USER)
docker build -t $DOCKER_USER/hpa-demo:1.0 .
docker push $DOCKER_USER/hpa-demo:1.0
kubectl apply -f k8s-deployment.yaml -f k8s-service.yaml -f k8s-hpa.yaml
kubectl set image deployment/hpa-demo app=$DOCKER_USER/hpa-demo:1.0
kubectl rollout status deployment/hpa-demo
```

4. Genera carga y monitoriza HPA:

```bash
kubectl run -it --rm loadgen --image=curlimages/curl --restart=Never -- \
  sh -c 'for i in {1..200}; do curl -s http://hpa-demo:8000/cpu?duration=3&intensity=2 >/dev/null; done'
kubectl get hpa hpa-demo --watch
```

### AKS (Azure Kubernetes Service)

1. Crea o usa un cluster AKS y obtén credenciales:

```bash
az login
az group create -n myResourceGroup -l eastus
az aks create -g myResourceGroup -n myAKSCluster --node-count 2 --generate-ssh-keys
az aks get-credentials -g myResourceGroup -n myAKSCluster
```

2. Opciones para la imagen:

- Push a Docker Hub y usar `deploy.sh` (con $DOCKER_USER):

```bash
TAG=1.0 ./deploy.sh
```

- O push a Azure Container Registry (ACR):

```bash
# Crear ACR
az acr create -g myResourceGroup -n myRegistry --sku Basic
az acr login --name myRegistry
docker build -t myregistry.azurecr.io/hpa-demo:1.0 .
docker push myregistry.azurecr.io/hpa-demo:1.0
# Permitir AKS a tirar imagenes desde ACR (si creado en mismo subscription)
az aks update -n myAKSCluster -g myResourceGroup --attach-acr myRegistry
kubectl set image deployment/hpa-demo app=myregistry.azurecr.io/hpa-demo:1.0
kubectl rollout status deployment/hpa-demo
```

3. Genera carga y monitoriza HPA como en los ejemplos anteriores.

---

Notas comunes:

- Los archivos de manifest referenciados están en: [k8s-deployment.yaml](k8s-deployment.yaml), [k8s-service.yaml](k8s-service.yaml), [k8s-hpa.yaml](k8s-hpa.yaml) y el `deploy.sh` en [deploy.sh](deploy.sh).
- Si usas registry privado, crea `imagePullSecrets` y referencia en `k8s-deployment.yaml`.
- Asegúrate de que `resources.requests.cpu` están presentes (HPA las necesita).


### Generate CPU Load to Trigger Scaling

```bash
### Generate CPU Load to Trigger Scaling

```bash
# Port forward to service (service uses port 8000)
kubectl port-forward svc/hpa-demo 8000:8000 &

# Generate load from inside cluster (recommended)
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  sh -c 'for i in {1..100}; do curl http://hpa-demo:8000/cpu?duration=3&intensity=2; done'

# Or use ab from pod
kubectl run -it --rm load-test --image=httpd:2.4-alpine --restart=Never -- \
  ab -n 1000 -c 20 http://hpa-demo:8000/cpu?duration=5&intensity=2
```

### Watch Scaling

In another terminal:

```bash
kubectl get hpa hpa-demo --watch
kubectl get pods --watch
```

You should see pods scale up when CPU usage exceeds 50%, and scale down after stabilization.

## Validate HPA is Working

### Quick Check

```bash
# Ver si HPA escaló (debe mostrar > 2 replicas si hubo carga)
kubectl get pods -l app=hpa-demo

# Ver estado del HPA
kubectl get hpa hpa-demo

# Ver métricas en tiempo real
kubectl top pods -l app=hpa-demo
```

### Detailed Status

```bash
# En bash/WSL
kubectl describe hpa hpa-demo | grep -A 5 "Conditions:"

# En PowerShell
kubectl describe hpa hpa-demo | Select-String -A 5 "Conditions:"
```

Debería mostrar:
- `ScalingActive   True` — HPA está activo y monitoreando
- `Metrics: ... cpu: X%/50%` — Está capturando métricas de CPU

## Troubleshooting

### Check if metrics are available

```bash
kubectl get deployment hpa-demo
kubectl top pods -l app=hpa-demo
kubectl top nodes
```

### If HPA not scaling, check:

1. Metrics server is running: `kubectl get deployment metrics-server -n kube-system`
2. Pod resource requests are set (they are in the deployment)
3. HPA status: `kubectl describe hpa hpa-demo`
4. Pod logs for errors: `kubectl logs -l app=hpa-demo --tail=20`

## Configuration

Edit `k8s-hpa.yaml` to adjust:

- `minReplicas`: Minimum number of pods (default: 2)
- `maxReplicas`: Maximum number of pods (default: 10)
- `averageUtilization`: CPU threshold to trigger scaling (default: 50%)
- `stabilizationWindowSeconds`: Wait time before scaling down (default: 300s)
