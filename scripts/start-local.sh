#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo -e "\n Starting Local Kubernetes Environment (Kind + Helm)...\n"

# 1. Kind 클러스터 체크 및 생성
if ! kind get clusters | grep -q "kafka-demo"; then
    echo "Creating Kind cluster 'kafka-demo' with config..."
    kind create cluster --name kafka-demo --config deploy/kind/kind-config.yaml
else
    echo "Kind cluster 'kafka-demo' already exists."
fi

# 2. KEDA 설치
echo -e "\nStep 1: Installing KEDA Operator..."
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.12.0/keda-2.12.0.yaml
echo "Waiting for KEDA Operator..."
kubectl wait --for=condition=available --timeout=120s deployment/keda-operator -n keda

# 3. Docker Image Build & Load
echo -e "\nStep 2: Building & Loading Docker Image..."
docker build -t my-log-service:latest .
kind load docker-image my-log-service:latest --name kafka-demo

# 4. Namespace 생성
echo -e "\nStep 2-1: Creating Namespace..."
kubectl create namespace kafka-demo --dry-run=client -o yaml | kubectl apply -f -

# 5. Helm Chart 설치/업데이트
echo -e "\nStep 3: Deploying Kafka-Demo via Helm..."
helm upgrade --install kafka-demo ./charts/kafka-demo \
  -f charts/kafka-demo/values-local.yaml \
  --namespace kafka-demo \
  --create-namespace

echo -e "\nDeployment complete!"
echo "Check status : make status"
echo "Kafka UI     : make proxy  ->  http://localhost:8090"
echo "Logs         : make logs"
