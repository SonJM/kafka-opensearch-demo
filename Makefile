.PHONY: up down clean status check-keda logs proxy k9s hmac package dev-deploy nexus-push keda-install

# ─────────────────────────────────────────────
# 로컬 환경 (Kind)
# ─────────────────────────────────────────────

# Kind 클러스터 생성 + KEDA + Helm 배포
up:
	@bash scripts/start-local.sh

# Helm release만 제거 (클러스터 유지)
down:
	@echo "Uninstalling Helm release..."
	@helm uninstall kafka-demo -n kafka-demo || echo "Already uninstalled"

# Kind 클러스터 삭제 (down 선행)
clean: down
	@echo "Deleting Kind cluster 'kafka-demo'..."
	@kind delete cluster --name kafka-demo

# ─────────────────────────────────────────────
# 공통 유틸리티
# ─────────────────────────────────────────────

# 클러스터 상태 확인
status:
	@bash scripts/check-status.sh

# KEDA ScaledObject 상태 확인
check-keda:
	@kubectl get scaledobjects -n kafka-demo
	@kubectl get pods -n keda

# 주요 앱 로그 tail
logs:
	@kubectl logs -f -n kafka-demo -l app=my-log-service --all-containers --max-log-requests=10

# 로컬 서비스 port-forward
proxy:
	@echo "Kafka UI    : http://localhost:8090"
	@echo "OpenSearch  : http://localhost:9200"
	@echo "Ctrl+C to stop."
	@kubectl port-forward svc/kafka-ui 8090:8090 -n kafka-demo & \
	 kubectl port-forward svc/opensearch 9200:9200 -n kafka-demo

# k9s 실행
k9s:
	@k9s --context kind-kafka-demo -n kafka-demo

# HMAC 스크립트 실행
hmac:
	@bash scripts/hmac.sh

# ─────────────────────────────────────────────
# Air-gap 패키징 (Dev PC — 인터넷 연결 필요)
# ─────────────────────────────────────────────

# hauler store 경로 (Linux 네이티브 fs — NTFS rename 제한 우회)
HAULER_STORE := /opt/kafka-demo-hauler-store

# 단일 번들(.tar.zst) 생성 — install.sh 포함
# 번들 내 hauler가 직접 OCI 레지스트리로 서빙 (Nexus 불필요)
#
# 사전 조건: skopeo 설치 필요 (apt-get install -y skopeo)
#
# 폐쇄망 서버에서 설치 방법 (3줄):
#   hauler store -s /opt/kafka-demo-hauler-store load -f kafka-demo-airgap.tar.zst
#   hauler store -s /opt/kafka-demo-hauler-store extract hauler/install.sh:latest
#   chmod +x install.sh && ./install.sh
package:
	@echo ">>> [1/4] Syncing external resources into hauler store..."
	hauler store -s $(HAULER_STORE) sync -f deploy/airgap/hauler.yaml
	@echo ">>> [2/4] Copying local app image into hauler store..."
	skopeo copy --insecure-policy \
	  docker-archive:my-log-service.tar \
	  oci:$(HAULER_STORE):my-log-service:latest
	@echo ">>> [3/4] Adding install script to bundle..."
	hauler store -s $(HAULER_STORE) add file deploy/airgap/install.sh
	@echo ">>> [4/4] Saving bundle..."
	hauler store -s $(HAULER_STORE) save --filename kafka-demo-airgap.tar.zst
	@echo ">>> 전달 파일 준비..."
	cp ~/.hauler/hauler hauler-linux-amd64
	@echo "Done:"
	@echo "  kafka-demo-airgap.tar.zst  (번들)"
	@echo "  hauler-linux-amd64         (hauler 바이너리)"

# ─────────────────────────────────────────────
# 개발 서버 배포 (개발자 PC에서 실행)
# 사전 조건: RKE2 클러스터 kubeconfig 경로를 지정해야 함
#   export DEV_KUBECONFIG=/path/to/rke2.yaml
#   또는: make dev-deploy DEV_KUBECONFIG=/path/to/rke2.yaml
# ─────────────────────────────────────────────

DEV_REGISTRY   ?= 172.16.30.128:5000
DEV_KUBECONFIG ?= $(KUBECONFIG)

# hauler 번들의 모든 이미지를 Nexus에 push (최초 1회 또는 번들 갱신 시)
nexus-push:
	@echo ">>> Pushing all images from hauler store to Nexus ($(DEV_REGISTRY))..."
	hauler store -s $(HAULER_STORE) copy registry://$(DEV_REGISTRY) --plain-http
	@echo "Done: images pushed to $(DEV_REGISTRY)"

# KEDA를 Nexus 이미지로 설치 (개발 서버용)
keda-install:
	@[ -n "$(DEV_KUBECONFIG)" ] || (echo "ERROR: DEV_KUBECONFIG is not set.\n  export DEV_KUBECONFIG=/path/to/rke2.yaml" && exit 1)
	@echo ">>> Installing KEDA 2.12.0 from Nexus ($(DEV_REGISTRY))..."
	helm upgrade --install keda keda/keda \
	  --kubeconfig=$(DEV_KUBECONFIG) \
	  --namespace keda \
	  --create-namespace \
	  --version 2.12.0 \
	  --set image.keda.registry=$(DEV_REGISTRY) \
	  --set image.keda.repository=kedacore/keda \
	  --set image.metricsApiServer.registry=$(DEV_REGISTRY) \
	  --set image.metricsApiServer.repository=kedacore/keda-metrics-apiserver \
	  --set image.webhooks.registry=$(DEV_REGISTRY) \
	  --set image.webhooks.repository=kedacore/keda-admission-webhooks
	@echo "Done: KEDA installed"

# 사내 서비스 이미지 빌드 + Nexus push + helm 배포 (차트 또는 서비스 변경 시)
# - 이미지: my-log-service만 빌드하여 Nexus에 push
# - 차트: 로컬 ./charts/kafka-demo 직접 반영
dev-deploy:
	@[ -n "$(DEV_KUBECONFIG)" ] || (echo "ERROR: DEV_KUBECONFIG is not set.\n  export DEV_KUBECONFIG=/path/to/rke2.yaml  or  make dev-deploy DEV_KUBECONFIG=/path/to/rke2.yaml" && exit 1)
	@echo ">>> [1/3] Building my-log-service image..."
	docker build -t my-log-service:latest .
	docker tag my-log-service:latest $(DEV_REGISTRY)/my-log-service:latest
	docker push $(DEV_REGISTRY)/my-log-service:latest
	@echo ">>> [2/3] Restarting pods to apply new image..."
	kubectl --kubeconfig=$(DEV_KUBECONFIG) rollout restart deployment -n kafka-demo 2>/dev/null || true
	@echo ">>> [3/3] Deploying chart to dev server (registry=$(DEV_REGISTRY))..."
	helm upgrade --install kafka-demo ./charts/kafka-demo \
	  --kubeconfig=$(DEV_KUBECONFIG) \
	  --namespace kafka-demo \
	  --create-namespace \
	  --set global.registry=$(DEV_REGISTRY)
	@echo "Done: my-log-service built and kafka-demo deployed"
