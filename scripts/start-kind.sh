#!/bin/bash

# 프로젝트 루트 디렉토리로 이동
cd "$(dirname "$0")/.."

# 설정 변수
CLUSTER_NAME="kafka-demo"
IMAGE_NAME="my-log-service:latest"
NAMESPACE="kafka-demo"

echo "🚀 Starting Kafka Demo on Kind (WSL/Linux)..."

# 1. Kind Cluster Check & Create
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    echo "✅ Cluster '$CLUSTER_NAME' already exists."
else
    echo "📦 Creating Kind cluster '$CLUSTER_NAME'..."
    kind create cluster --name $CLUSTER_NAME
fi

# 2. Install KEDA Operator (Infrastructure)
echo "🔧 Installing KEDA Operator..."
kubectl apply --server-side -f deploy/k8s/keda-2.12.0.yaml --context kind-$CLUSTER_NAME

# Wait for KEDA CRDs to be established
echo "⏳ Waiting for KEDA CustomResourceDefinitions..."
kubectl wait --for=condition=established --timeout=60s crd/scaledobjects.keda.sh --context kind-$CLUSTER_NAME
kubectl wait --for=condition=established --timeout=60s crd/scaledjobs.keda.sh --context kind-$CLUSTER_NAME

# 3. Build & Load Application Image
echo "🐳 Building Docker Image ($IMAGE_NAME)..."
docker build -t $IMAGE_NAME .

echo "truck 🚚 Loading Image into Kind Node..."
kind load docker-image $IMAGE_NAME --name $CLUSTER_NAME

# 4. Deploy Helm Chart
echo "Helm ⚓ Installing/Upgrading Chart..."
helm upgrade --install kafka-demo ./charts/kafka-demo \
    --kube-context kind-$CLUSTER_NAME \
    --namespace $NAMESPACE \
    --create-namespace \
    --set global.environment=local \
    --set apps[0].image.pullPolicy=Never \
    --set apps[1].image.pullPolicy=Never \
    --set apps[2].image.pullPolicy=Never

# 5. Finalize
echo "✅ Deployment Complete!"
echo "👉 Run 'k9s' to monitor your cluster."
