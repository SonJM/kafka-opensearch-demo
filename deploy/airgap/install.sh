#!/bin/bash
# kafka-demo air-gap 설치 스크립트
#
# 사전 조건:
#   - hauler 바이너리가 PATH에 있어야 함 (/usr/local/bin/hauler 권장)
#   - helm 바이너리가 PATH에 있어야 함
#   - RKE2 클러스터가 실행 중이어야 함
#
# 사용법:
#   1. 번들 로드:
#        hauler store -s /opt/kafka-demo-hauler-store load -f kafka-demo-airgap.tar.zst
#   2. 스크립트 추출:
#        hauler store -s /opt/kafka-demo-hauler-store extract hauler/install.sh:latest
#   3. 실행:
#        chmod +x install.sh && ./install.sh
#
# 환경 변수로 재정의 가능:
#   REGISTRY_PORT=5000 NAMESPACE=kafka-demo STORE=/opt/kafka-demo-hauler-store ./install.sh

set -euo pipefail

STORE="${STORE:-/opt/kafka-demo-hauler-store}"
NAMESPACE="${NAMESPACE:-kafka-demo}"
REGISTRY_PORT="${REGISTRY_PORT:-5000}"

# 서버 자신의 IP 감지 (k8s 파드가 접근할 수 있는 주소)
LOCAL_IP=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
REGISTRY="${LOCAL_IP}:${REGISTRY_PORT}"

echo "============================================"
echo " kafka-demo air-gap 설치"
echo "  Hauler registry : http://${REGISTRY}"
echo "  Namespace       : ${NAMESPACE}"
echo "  Store           : ${STORE}"
echo "============================================"

# ── Step 1: hauler 레지스트리를 systemd 서비스로 등록 ──────────────────
echo ""
echo ">>> [1/4] hauler 레지스트리 서비스 등록 (port ${REGISTRY_PORT})..."

cat > /etc/systemd/system/hauler-registry.service << EOF
[Unit]
Description=Hauler Air-Gap OCI Registry
After=network.target

[Service]
ExecStart=$(which hauler) store -s ${STORE} serve registry --port ${REGISTRY_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now hauler-registry
echo "     hauler-registry 서비스 시작 완료"

# 레지스트리가 뜰 때까지 대기
for i in $(seq 1 10); do
  if curl -sf "http://${REGISTRY}/v2/" > /dev/null 2>&1; then
    echo "     레지스트리 응답 확인 (http://${REGISTRY}/v2/)"
    break
  fi
  echo "     대기 중... (${i}/10)"
  sleep 2
done

# ── Step 2: RKE2가 hauler 레지스트리를 신뢰하도록 설정 ─────────────────
echo ""
echo ">>> [2/4] RKE2 insecure registry 설정 (${REGISTRY})..."

mkdir -p /etc/rancher/rke2
cat > /etc/rancher/rke2/registries.yaml << EOF
configs:
  "${REGISTRY}":
    tls:
      insecure_skip_verify: true
EOF

# RKE2 재시작 (레지스트리 설정 적용)
if systemctl is-active --quiet rke2-server 2>/dev/null; then
  echo "     rke2-server 재시작..."
  systemctl restart rke2-server
  sleep 15
elif systemctl is-active --quiet rke2-agent 2>/dev/null; then
  echo "     rke2-agent 재시작..."
  systemctl restart rke2-agent
  sleep 15
else
  echo "     (RKE2 서비스 감지되지 않음 — 수동으로 containerd 재시작 필요할 수 있음)"
fi

# ── Step 3: Helm 차트 추출 ────────────────────────────────────────────
echo ""
echo ">>> [3/4] Helm 차트 추출..."
hauler store -s "${STORE}" extract hauler/kafka-demo:0.1.0

CHART=$(ls kafka-demo-*.tgz 2>/dev/null | head -1)
if [[ -z "${CHART}" ]]; then
  echo "ERROR: kafka-demo-*.tgz 파일을 찾을 수 없습니다."
  exit 1
fi

# ── Step 4: Helm 배포 ─────────────────────────────────────────────────
echo ""
echo ">>> [4/4] Helm 배포 (registry=${REGISTRY})..."
helm upgrade --install kafka-demo "${CHART}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set global.registry="${REGISTRY}"

echo ""
echo "============================================"
echo " 설치 완료"
echo "  이미지 레지스트리 : http://${REGISTRY}"
echo "  k8s 네임스페이스  : ${NAMESPACE}"
echo ""
echo "  서비스 상태 확인:"
echo "    systemctl status hauler-registry"
echo "    kubectl get pods -n ${NAMESPACE}"
echo "============================================"
