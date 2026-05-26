from fastapi import FastAPI, Query
from fastapi.responses import Response
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from concurrent.futures import ThreadPoolExecutor
import time
import os

app = FastAPI()

# Prometheus metrics
cpu_requests = Counter('cpu_requests_total', 'Total CPU requests')
cpu_duration = Histogram('cpu_request_duration_seconds', 'CPU request duration')

@app.get("/")
def home():
    return {
        "status": "ok",
        "version": "1.0",
        "endpoints": {
            "health": "/health",
            "cpu": "/cpu?duration=1&intensity=1",
            "metrics": "/metrics"
        }
    }

@app.get("/health")
def health():
    return {"status": "healthy"}

@app.get("/cpu")
def cpu(duration: float = Query(1.0, description="Duration in seconds"), 
        intensity: int = Query(1, description="Number of CPU cores to stress")):
    """
    CPU stress endpoint for HPA testing
    duration: How long to stress CPU (default 1 second)
    intensity: Number of parallel CPU tasks (default 1)
    """
    cpu_requests.inc()

    start = time.time()

    def _busy(dur: float):
        end = time.time() + dur
        cnt = 0
        while time.time() < end:
            cnt += 1
        return cnt

    intensity = max(1, int(intensity))
    # Use threads for CPU stressing (more compatible)
    with ThreadPoolExecutor(max_workers=intensity) as ex:
        futures = [ex.submit(_busy, duration) for _ in range(intensity)]
        results = [f.result() for f in futures]

    iterations = sum(results)
    elapsed = time.time() - start
    cpu_duration.observe(elapsed)

    return {
        "done": True,
        "iterations": iterations,
        "duration": elapsed,
        "intensity": intensity
    }

@app.get("/metrics")
def metrics():
    """Prometheus metrics endpoint"""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)