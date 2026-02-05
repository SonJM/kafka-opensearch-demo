#!/bin/bash
set -e

# 프로젝트 루트 디렉토리로 이동
cd "$(dirname "$0")/.."

echo -e "\n🚀 Starting Local Kubernetes Environment (Kind + Helm)...\n"

# 1. Kind 클러스터 체크 및 생성
if ! kind get clusters | grep -q "kafka-demo"; then
    echo "Creating Kind cluster 'kafka-demo' with port mappings..."
    kind create cluster --name kafka-demo --config deploy/kind/kind-config.yaml
else
    echo "Kind cluster 'kafka-demo' already exists."
fi

# 2. KEDA 설치 (Operator)
echo -e "\nStep 1: Installing KEDA Operator..."
kubectl apply --server-side -f deploy/k8s/keda-2.12.0.yaml
echo "⏳ Waiting for KEDA Operator..."
kubectl wait --for=condition=available --timeout=120s deployment/keda-operator -n keda

# 3. Docker Image Build & Load (For Local Kind)
echo -e "\nStep 2: Building & Loading Docker Image..."
docker build -t my-log-service:latest .
kind load docker-image my-log-service:latest --name kafka-demo

# 3-1. Namespace 생성 (안전장치)
echo -e "\nStep 2-1: Creating Namespace..."
kubectl create namespace kafka-demo --dry-run=client -o yaml | kubectl apply -f -

# 4. Helm Chart 설치/업데이트
echo -e "\nStep 3: Deploying Kafka-Demo via Helm..."
# -f charts/kafka-demo/values-local.yaml 를 사용하여 로컬용 설정 적용
helm upgrade --install kafka-demo ./charts/kafka-demo \
  -f charts/kafka-demo/values-local.yaml \
  --namespace kafka-demo \
  --create-namespace

echo -e "\n✅ Deployment command sent!"
echo "⏳ Resources are starting up. Please check status with 'make status' or 'make k9s'."

echo -e "\n✅ All resources deployed successfully via Helm!"
echo "👉 Check status: kubectl get pods -n kafka-demo"
echo "👉 Kafka UI: http://localhost:8090 (if using LoadBalancer/Port-forward)"