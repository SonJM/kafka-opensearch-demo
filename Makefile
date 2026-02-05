.PHONY: up down status check-keda clean hmac logs

# 환경 기동 (Local Kind + Helm)
up:
	@bash scripts/start-local.sh

# 환경 중단 (Helm 앱만 제거)
down:
	@echo "🗑️  Uninstalling Helm release..."
	@helm uninstall kafka-demo -n kafka-demo || echo "Release already uninstalled"

# 클러스터 상태 확인
status:
	@bash scripts/check-status.sh

# KEDA 상태 상세 확인
check-keda:
	@kubectl get scaledobjects -n kafka-demo
	@kubectl get pods -n keda

# 환경 삭제 (Kind Cluster 삭제)
clean: down
	@echo "🔥 Deleting Kind cluster 'kafka-demo'..."
	@kind delete cluster --name kafka-demo

# HMAC 데이터 관리 스크립트 실행
hmac:
	@bash scripts/hmac.sh

# 주요 앱 로그 확인 (Tail)
logs:
	@kubectl logs -f -n kafka-demo -l app=my-log-service --all-containers --max-log-requests=10

# 온프레미스 납품용 패키징 (Air-gap)
# 이미지 빌드 -> tar 저장 -> Hauler 동기화 -> 단일 압축파일 생성
package:
	@echo "📦 Building application image..."
	docker build -t my-log-service:latest .
	@echo "💾 Saving image to tarball for Hauler..."
	docker save my-log-service:latest -o my-log-service.tar
	@echo "🔄 Syncing resources with Hauler (BOM: deploy/kind/hauler.yaml)..."
	hauler store sync -f deploy/kind/hauler.yaml
	@echo "📦 Creating final air-gap bundle (kafka-demo-airgap.tar.zst)..."
	hauler store save --filename kafka-demo-airgap.tar.zst
	@echo "✅ Packaging Complete: kafka-demo-airgap.tar.zst"

# 폐쇄망 배포 데모 (로컬 레지스트리/파일 서버 구동)
serve:
	@echo "🚀 Starting Hauler Air-gap Registry & File Server..."
	@echo "Registry: localhost:5000 | File Server: localhost:8080"
	hauler store serve registry -p 5000 --files-port 8080 kafka-demo-airgap.tar.zst

# 모니터링 및 접속 도구
k9s:
	@echo "🚀 Launching k9s..."
	@k9s --context kind-kafka-demo -n kafka-demo

proxy:
	@echo "🔗 Kafka UI: http://localhost:8090"
	@echo "🔗 OpenSearch: http://localhost:9200"
	@echo "⌨️ Press Ctrl+C to stop proxy."
	@kubectl port-forward svc/kafka-ui 8090:8090 -n kafka-demo & \
	 kubectl port-forward svc/opensearch 9200:9200 -n kafka-demo
