#!/bin/bash

# 프로젝트 루트 디렉토리로 이동
cd "$(dirname "$0")/.."

echo "🔍 Checking Kafka Demo Status..."

# 1. Check Cluster
if ! kind get clusters | grep -q "kafka-demo"; then
    echo "❌ Kind cluster 'kafka-demo' NOT found!"
    exit 1
else
    echo "✅ Kind cluster 'kafka-demo' exists."
fi

# 2. Check Context
CURRENT_CTX=$(kubectl config current-context)
if [ "$CURRENT_CTX" != "kind-kafka-demo" ]; then
    echo "⚠️  Current context is '$CURRENT_CTX'. Switching to 'kind-kafka-demo'..."
    kubectl config use-context kind-kafka-demo
else
    echo "✅ Context is correct."
fi

# 3. Check Helm Release
echo -e "\n📊 Helm Release Status:"
helm list -n kafka-demo -a

# 4. Check Pods
echo -e "\n📦 Pod Status:"
kubectl get pods -n kafka-demo

# 5. Check Events (If pods are missing or pending)
echo -e "\n⚠️  Recent Events (Errors/Warnings):"
kubectl get events -n kafka-demo --sort-by='.lastTimestamp' | tail -n 10

echo -e "\n🚀 Diagnosis Complete."
