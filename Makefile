.PHONY: up down clean status check-keda logs proxy k9s hmac package push deploy

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

# 단일 번들(.tar.zst) 생성
# 1) 앱 이미지 빌드
# 2) 외부 이미지/파일/chart hauler store에 pull
# 3) 로컬 빌드 이미지를 Image 타입으로 store에 추가
# 4) 번들 저장
package:
	@echo ">>> [1/4] Building application image..."
	docker build -t my-log-service:latest .
	@echo ">>> [2/4] Syncing external resources into hauler store..."
	hauler store sync -f deploy/airgap/hauler.yaml
	@echo ">>> [3/4] Adding local app image to hauler store..."
	hauler store add image my-log-service:latest --platform linux/amd64
	@echo ">>> [4/4] Saving bundle..."
	hauler store save --filename kafka-demo-airgap.tar.zst
	@echo "Done: kafka-demo-airgap.tar.zst"

# ─────────────────────────────────────────────
# Air-gap 배포 (폐쇄망 서버에서 실행)
# ─────────────────────────────────────────────

# 번들을 Nexus Docker registry에 push
# 사전 조건: kafka-demo-airgap.tar.zst 파일이 현재 디렉토리에 있어야 함
push:
	@echo ">>> [1/2] Loading bundle into hauler store..."
	hauler store load kafka-demo-airgap.tar.zst
	@echo ">>> [2/2] Pushing images to Nexus (172.16.30.128:5000)..."
	hauler store copy registry://172.16.30.128:5000 --plain-http
	@echo "Done: images pushed to 172.16.30.128:5000"

# RKE2 클러스터에 Helm 배포
# global.registry는 values.yaml 기본값(172.16.30.128:5000) 사용
deploy:
	@echo ">>> Deploying kafka-demo to RKE2 cluster..."
	helm upgrade --install kafka-demo ./charts/kafka-demo \
	  --namespace kafka-demo \
	  --create-namespace
	@echo "Done: helm release kafka-demo deployed"
