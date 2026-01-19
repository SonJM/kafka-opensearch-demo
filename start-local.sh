#!/bin/bash
set -e

echo -e "\n🚀 Starting Local Kubernetes Environment (Kind + Helm)...\n"

# 1. Kind 클러스터 체크 및 생성
if ! kind get clusters | grep -q "kafka-demo"; then
    echo "Creating Kind cluster 'kafka-demo'..."
    kind create cluster --name kafka-demo
else
    echo "Kind cluster 'kafka-demo' already exists."
fi

# 2. KEDA 설치 (Operator)
echo -e "\nStep 1: Installing KEDA Operator..."
kubectl apply -f k8s/keda-2.12.0.yaml
echo "⏳ Waiting for KEDA Operator..."
kubectl wait --for=condition=available --timeout=120s deployment/keda-operator -n keda

# 3. Helm Chart 설치/업데이트
echo -e "\nStep 2: Deploying Kafka-Demo via Helm..."
# -f charts/kafka-demo/values-local.yaml 를 사용하여 로컬용 설정 적용
helm upgrade --install kafka-demo ./charts/kafka-demo \
  -f charts/kafka-demo/values-local.yaml \
  --namespace kafka-demo \
  --create-namespace \
  --wait

echo -e "\n✅ All resources deployed successfully via Helm!"
echo "👉 Check status: kubectl get pods -n kafka-demo"
echo "👉 Kafka UI: http://localhost:8090 (if using LoadBalancer/Port-forward)"