# Air-gap 배포 파이프라인 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kind(로컬) ↔ RKE2(배포) 환경을 명확히 분리하고, Hauler v1alpha2 기반으로 단일 번들을 생성해 Nexus(172.16.30.128:5000)에 push하는 수동 CD 파이프라인을 구축한다.

**Architecture:** Dev PC에서 `make package`로 번들(.tar.zst)을 생성 → 폐쇄망 서버에서 `make push`로 Nexus에 push → RKE2 클러스터에서 `make deploy`로 Helm 배포. 로컬 테스트는 Kind + `values-local.yaml`로 완전히 분리한다.

**Tech Stack:** Hauler v1alpha2, Helm 3, Kind, RKE2, Nexus Docker hosted registry(172.16.30.128:5000), KEDA 2.12.0

---

## 파일 변경 맵

| 액션 | 경로 | 역할 |
|------|------|------|
| 삭제 | `scripts/start-kind.sh` | start-local.sh와 중복 |
| 삭제 | `deploy/k8s/` (디렉토리 전체) | Helm chart로 대체됨 |
| 삭제 | `deploy/kind/hauler.yaml` | deploy/airgap/으로 이동 |
| 생성 | `deploy/airgap/hauler.yaml` | Hauler BOM v1alpha2 |
| 수정 | `charts/kafka-demo/values.yaml` | RKE2 기본값(global.registry 등) |
| 수정 | `charts/kafka-demo/values-local.yaml` | Kind 오버라이드 정비 |
| 수정 | `charts/kafka-demo/templates/30-apps.yaml` | imagePullPolicy를 values에서 읽도록 |
| 수정 | `charts/kafka-demo/templates/50-tools.yaml` | kafka-ui registry 적용, log-generator 교체 |
| 수정 | `deploy/kind/kind-config.yaml` | 미사용 NodePort 매핑 제거 |
| 수정 | `scripts/start-local.sh` | keda manifest 경로 업데이트 |
| 수정 | `Makefile` | package/push/deploy 타겟 재작성, serve 제거 |

---

## Task 1: 불필요한 파일 삭제 및 디렉토리 구조 정비

**Files:**
- Delete: `scripts/start-kind.sh`
- Delete: `deploy/k8s/` (전체)
- Delete: `deploy/kind/hauler.yaml`
- Create dir: `deploy/airgap/`

- [ ] **Step 1: 중복 스크립트 삭제**

```bash
rm scripts/start-kind.sh
```

- [ ] **Step 2: 대체된 raw YAML 디렉토리 삭제**

```bash
rm -rf deploy/k8s/
```

- [ ] **Step 3: 기존 hauler.yaml 삭제 (새 위치로 이동 예정)**

```bash
rm deploy/kind/hauler.yaml
```

- [ ] **Step 4: airgap 디렉토리 생성**

```bash
mkdir -p deploy/airgap
```

- [ ] **Step 5: 삭제 결과 확인**

```bash
ls scripts/
ls deploy/
```

Expected:
```
scripts/:
check-status.sh  hmac.sh  start-local.sh

deploy/:
airgap/  kind/
```

- [ ] **Step 6: 커밋**

```bash
git add -A
git commit -m "chore: remove redundant files and restructure deploy directory"
```

---

## Task 2: Hauler BOM 재작성 (v1alpha2, deploy/airgap/hauler.yaml)

**Files:**
- Create: `deploy/airgap/hauler.yaml`

> **주의:** `my-log-service`는 공개 registry가 없어 hauler sync 시 pull 불가. Images 목록에서 제외하고 `make package`에서 `hauler store add image`로 직접 주입한다.

- [ ] **Step 1: hauler.yaml 작성**

`deploy/airgap/hauler.yaml` 파일을 아래 내용으로 생성한다:

```yaml
apiVersion: content.hauler.cattle.io/v1alpha2
kind: Files
metadata:
  name: kafka-demo-files
spec:
  files:
    - path: https://get.rke2.io/install.sh
      name: rke2-install.sh
    - path: https://github.com/rancher/rke2/releases/download/v1.28.4%2Brke2r1/rke2.linux-amd64.tar.gz
      name: rke2.linux-amd64.tar.gz
    - path: https://github.com/rancher/rke2/releases/download/v1.28.4%2Brke2r1/rke2-images.linux-amd64.tar.zst
      name: rke2-images.linux-amd64.tar.zst
    - path: https://github.com/derailed/k9s/releases/download/v0.32.4/k9s_Linux_amd64.tar.gz
      name: k9s.tar.gz
    - path: https://get.helm.sh/helm-v3.13.2-linux-amd64.tar.gz
      name: helm-v3.13.2.tar.gz
    - path: https://github.com/kedacore/keda/releases/download/v2.12.0/keda-2.12.0.yaml
      name: keda-2.12.0.yaml

---
apiVersion: content.hauler.cattle.io/v1alpha2
kind: Images
metadata:
  name: kafka-demo-images
spec:
  images:
    - name: apache/kafka:4.1.1
    - name: opensearchproject/opensearch:2.11.1
    - name: provectuslabs/kafka-ui:v0.7.2
    - name: busybox:1.36
    - name: ghcr.io/kedacore/keda:2.12.0
    - name: ghcr.io/kedacore/keda-metrics-apiserver:2.12.0
    - name: ghcr.io/kedacore/keda-admission-webhooks:2.12.0

---
apiVersion: content.hauler.cattle.io/v1alpha2
kind: Charts
metadata:
  name: kafka-demo-charts
spec:
  charts:
    - name: kafka-demo
      repoURL: ./charts/kafka-demo
```

- [ ] **Step 2: 문법 확인 (hauler가 설치된 환경에서 실행)**

```bash
hauler store sync -f deploy/airgap/hauler.yaml --dry-run 2>&1 | head -20
```

dry-run을 지원하지 않는 경우 다음으로 apiVersion 확인:

```bash
hauler version
```

- [ ] **Step 3: 커밋**

```bash
git add deploy/airgap/hauler.yaml
git commit -m "feat: add hauler BOM v1alpha2 with pinned image versions"
```

---

## Task 3: Helm values.yaml — RKE2 기본값 설정

**Files:**
- Modify: `charts/kafka-demo/values.yaml`

- [ ] **Step 1: values.yaml 전체 교체**

`charts/kafka-demo/values.yaml`:

```yaml
global:
  registry: "172.16.30.128:5000"
  environment: production

license:
  tier: basic # basic | pro | enterprise

kafka:
  image:
    repository: apache/kafka
    tag: 4.1.1
  storage: 1Gi

opensearch:
  image:
    repository: opensearchproject/opensearch
    tag: 2.11.1
  ui:
    port: 9200

kafkaUI:
  image:
    repository: provectuslabs/kafka-ui
    tag: "v0.7.2"

apps:
  - name: w1-service
    image:
      repository: my-log-service
      tag: latest
      pullPolicy: IfNotPresent
    role: W1
    kafka:
      inputTopic: topic-a
      outputTopic1: topic-b
      outputTopic2: topic-c
      consumerGroup: group-W1
      lagThreshold: "10"

  - name: w2-service
    image:
      repository: my-log-service
      tag: latest
      pullPolicy: IfNotPresent
    role: W2
    kafka:
      inputTopic: topic-b
      consumerGroup: group-W2
      lagThreshold: "10"

  - name: w3-service
    image:
      repository: my-log-service
      tag: latest
      pullPolicy: IfNotPresent
    role: W3
    kafka:
      inputTopic: topic-c
      consumerGroup: group-W3
      lagThreshold: "10"

logGenerator:
  image:
    repository: apache/kafka
    tag: 4.1.1
    pullPolicy: IfNotPresent
  enabled: true
```

- [ ] **Step 2: helm template으로 렌더링 확인 (RKE2 기본값)**

```bash
helm template kafka-demo ./charts/kafka-demo | grep -E "image:|imagePullPolicy:" | head -20
```

Expected: 모든 image 앞에 `172.16.30.128:5000/` 프리픽스가 붙어있고, pullPolicy가 `IfNotPresent`

- [ ] **Step 3: 커밋**

```bash
git add charts/kafka-demo/values.yaml
git commit -m "feat: set RKE2 registry defaults in values.yaml"
```

---

## Task 4: Helm values-local.yaml — Kind 오버라이드 정비

**Files:**
- Modify: `charts/kafka-demo/values-local.yaml`

- [ ] **Step 1: values-local.yaml 전체 교체**

`charts/kafka-demo/values-local.yaml`:

```yaml
global:
  registry: ""
  environment: local

license:
  tier: pro

kafka:
  storage: 100Mi

apps:
  - name: w1-service
    image:
      repository: my-log-service
      tag: latest
      pullPolicy: Never
    role: W1
    kafka:
      inputTopic: topic-a
      outputTopic1: topic-b
      outputTopic2: topic-c
      consumerGroup: group-W1
      lagThreshold: "5000"

  - name: w2-service
    image:
      repository: my-log-service
      tag: latest
      pullPolicy: Never
    role: W2
    kafka:
      inputTopic: topic-b
      consumerGroup: group-W2
      lagThreshold: "500"

  - name: w3-service
    image:
      repository: my-log-service
      tag: latest
      pullPolicy: Never
    role: W3
    kafka:
      inputTopic: topic-c
      consumerGroup: group-W3
      lagThreshold: "500"

```

> **참고:** `logGenerator`는 `apache/kafka` 공개 이미지를 사용하므로 Kind에서 Docker Hub pull이 가능하다. `pullPolicy: Never` 설정 불필요.

- [ ] **Step 2: helm template으로 로컬 렌더링 확인**

```bash
helm template kafka-demo ./charts/kafka-demo -f charts/kafka-demo/values-local.yaml \
  | grep -E "image:|imagePullPolicy:" | head -20
```

Expected: image 앞에 registry 프리픽스 없음, w1/w2/w3는 `pullPolicy: Never`

- [ ] **Step 3: 커밋**

```bash
git add charts/kafka-demo/values-local.yaml
git commit -m "feat: clean up values-local.yaml for Kind environment"
```

---

## Task 5: 30-apps.yaml — imagePullPolicy를 values에서 읽도록 수정

**Files:**
- Modify: `charts/kafka-demo/templates/30-apps.yaml:26`

현재 `imagePullPolicy: IfNotPresent`가 하드코딩되어 있어 `values-local.yaml`의 `pullPolicy: Never` 설정이 무시된다.

- [ ] **Step 1: imagePullPolicy 라인 수정**

`charts/kafka-demo/templates/30-apps.yaml` 의 26번째 줄을 수정한다:

```yaml
          imagePullPolicy: {{ .image.pullPolicy | default "IfNotPresent" }}
```

수정 후 전체 containers 섹션:

```yaml
      containers:
        - name: app
          image: "{{ if $.Values.global.registry }}{{ $.Values.global.registry }}/{{ end }}{{ .image.repository }}:{{ .image.tag }}"
          imagePullPolicy: {{ .image.pullPolicy | default "IfNotPresent" }}
          env:
```

- [ ] **Step 2: 로컬 values로 렌더링하여 Never 확인**

```bash
helm template kafka-demo ./charts/kafka-demo -f charts/kafka-demo/values-local.yaml \
  | grep -A2 "name: app" | grep imagePullPolicy
```

Expected:
```
          imagePullPolicy: Never
          imagePullPolicy: Never
          imagePullPolicy: Never
```

- [ ] **Step 3: RKE2 values로 렌더링하여 IfNotPresent 확인**

```bash
helm template kafka-demo ./charts/kafka-demo \
  | grep -A2 "name: app" | grep imagePullPolicy
```

Expected:
```
          imagePullPolicy: IfNotPresent
          imagePullPolicy: IfNotPresent
          imagePullPolicy: IfNotPresent
```

- [ ] **Step 4: 커밋**

```bash
git add charts/kafka-demo/templates/30-apps.yaml
git commit -m "fix: read imagePullPolicy from values instead of hardcoding"
```

---

## Task 6: 50-tools.yaml — kafka-ui registry 적용 및 log-generator 교체

**Files:**
- Modify: `charts/kafka-demo/templates/50-tools.yaml`

두 가지 문제 수정:
1. `kafka-ui` 이미지가 하드코딩되어 `global.registry` 미적용
2. `log-generator`가 런타임 `pip install` 수행 (air-gap 불가)

- [ ] **Step 1: 50-tools.yaml 전체 교체**

`charts/kafka-demo/templates/50-tools.yaml`:

```yaml
# Kafka UI
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
  namespace: {{ .Release.Namespace }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-ui
  template:
    metadata:
      labels:
        app: kafka-ui
    spec:
      containers:
        - name: kafka-ui
          image: "{{ if .Values.global.registry }}{{ .Values.global.registry }}/{{ end }}{{ .Values.kafkaUI.image.repository }}:{{ .Values.kafkaUI.image.tag }}"
          imagePullPolicy: {{ .Values.kafkaUI.image.pullPolicy | default "IfNotPresent" }}
          env:
            - name: KAFKA_CLUSTERS_0_NAME
              value: local
            - name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS
              value: kafka-headless:9092
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui
  namespace: {{ .Release.Namespace }}
spec:
  selector:
    app: kafka-ui
  type: LoadBalancer
  ports:
    - port: 8090
      targetPort: 8080

---
# Log Generator (Optional)
{{- if .Values.logGenerator.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: log-generator
  namespace: {{ .Release.Namespace }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: log-generator
  template:
    metadata:
      labels:
        app: log-generator
    spec:
      containers:
        - name: log-gen
          image: "{{ if .Values.global.registry }}{{ .Values.global.registry }}/{{ end }}{{ .Values.logGenerator.image.repository }}:{{ .Values.logGenerator.image.tag }}"
          imagePullPolicy: {{ .Values.logGenerator.image.pullPolicy | default "IfNotPresent" }}
          command: ["/bin/bash", "-c"]
          args:
            - |
              echo "Starting Log Generator (kafka-console-producer)..."
              while true; do
                count=$((RANDOM % 91 + 10))
                for i in $(seq 1 $count); do
                  printf '{"level":"INFO","message":"Log entry %s","timestamp":"%s"}\n' \
                    "$i" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
                done | /opt/kafka/bin/kafka-console-producer.sh \
                  --bootstrap-server kafka-headless:9092 \
                  --topic topic-a
                echo "Sent $count messages"
                sleep 1
              done
{{- end }}

---
# Init Kafka Topics
apiVersion: batch/v1
kind: Job
metadata:
  name: init-kafka-topics
  namespace: {{ .Release.Namespace }}
spec:
  ttlSecondsAfterFinished: 60
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: init-kafka
          image: "{{ if .Values.global.registry }}{{ .Values.global.registry }}/{{ end }}{{ .Values.kafka.image.repository }}:{{ .Values.kafka.image.tag }}"
          command: ["/bin/bash", "-c"]
          args:
            - |
              echo "Waiting for Kafka..."
              sleep 10
              echo "Creating topics..."
              /opt/kafka/bin/kafka-topics.sh --create --if-not-exists \
                --bootstrap-server kafka-headless:9092 \
                --partitions 3 --replication-factor 1 --topic topic-a
              /opt/kafka/bin/kafka-topics.sh --create --if-not-exists \
                --bootstrap-server kafka-headless:9092 \
                --partitions 3 --replication-factor 1 --topic topic-b
              /opt/kafka/bin/kafka-topics.sh --create --if-not-exists \
                --bootstrap-server kafka-headless:9092 \
                --partitions 3 --replication-factor 1 --topic topic-c
```

- [ ] **Step 2: kafka-ui에 registry 프리픽스 확인**

```bash
helm template kafka-demo ./charts/kafka-demo \
  | grep -A1 "name: kafka-ui" | grep image:
```

Expected:
```
          image: 172.16.30.128:5000/provectuslabs/kafka-ui:v0.7.2
```

- [ ] **Step 3: 로컬 values로 registry 없는지 확인**

```bash
helm template kafka-demo ./charts/kafka-demo -f charts/kafka-demo/values-local.yaml \
  | grep -E "image: .*kafka-ui|image: .*kafka:4|image: .*log"
```

Expected: `172.16.30.128:5000` 없이 이미지명만 출력

- [ ] **Step 4: 커밋**

```bash
git add charts/kafka-demo/templates/50-tools.yaml
git commit -m "fix: apply global.registry to kafka-ui, replace log-generator with kafka-console-producer"
```

---

## Task 7: kind-config.yaml — 미사용 NodePort 매핑 제거

**Files:**
- Modify: `deploy/kind/kind-config.yaml`

현재 30080/30081 NodePort 매핑이 있으나 실제 서비스에서 사용되지 않음. 로컬 접근은 `make proxy`(port-forward)로 통일.

- [ ] **Step 1: kind-config.yaml 교체**

`deploy/kind/kind-config.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
```

- [ ] **Step 2: 커밋**

```bash
git add deploy/kind/kind-config.yaml
git commit -m "chore: remove unused NodePort mappings from kind config"
```

---

## Task 8: start-local.sh — keda manifest 경로 업데이트

**Files:**
- Modify: `scripts/start-local.sh`

`deploy/k8s/keda-2.12.0.yaml`이 삭제되었으므로, KEDA를 GitHub release에서 직접 받거나 hauler bundle에서 가져오는 방식으로 변경한다. 로컬에서는 인터넷 연결이 가능하므로 공식 URL에서 직접 적용한다.

- [ ] **Step 1: start-local.sh 의 keda apply 줄 수정**

현재:
```bash
kubectl apply --server-side -f deploy/k8s/keda-2.12.0.yaml
```

변경 후:
```bash
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.12.0/keda-2.12.0.yaml
```

수정 후 전체 파일 (`scripts/start-local.sh`):

```bash
#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo -e "\n🚀 Starting Local Kubernetes Environment (Kind + Helm)...\n"

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

echo -e "\n✅ Deployment complete!"
echo "Check status : make status"
echo "Kafka UI     : make proxy  →  http://localhost:8090"
echo "Logs         : make logs"
```

- [ ] **Step 2: 스크립트 실행 권한 확인**

```bash
ls -la scripts/start-local.sh
```

권한이 없으면:
```bash
chmod +x scripts/start-local.sh
```

- [ ] **Step 3: 커밋**

```bash
git add scripts/start-local.sh
git commit -m "fix: update KEDA manifest URL, remove deleted k8s path reference"
```

---

## Task 9: Makefile 전면 재작성

**Files:**
- Modify: `Makefile`

`serve` 제거, `package`/`push`/`deploy` 재작성, `.PHONY` 정비.

- [ ] **Step 1: Makefile 전체 교체**

`Makefile`:

```makefile
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
	hauler store add image my-log-service:latest
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
	hauler store copy registry://172.16.30.128:5000
	@echo "Done: images pushed to 172.16.30.128:5000"

# RKE2 클러스터에 Helm 배포
# global.registry는 values.yaml 기본값(172.16.30.128:5000) 사용
deploy:
	@echo ">>> Deploying kafka-demo to RKE2 cluster..."
	helm upgrade --install kafka-demo ./charts/kafka-demo \
	  --namespace kafka-demo \
	  --create-namespace
	@echo "Done: helm release kafka-demo deployed"
```

- [ ] **Step 2: Makefile 문법 확인**

```bash
make --dry-run up 2>&1 | head -5
make --dry-run package 2>&1 | head -10
```

Expected: 실제 명령어가 출력되고 오류 없음

- [ ] **Step 3: 커밋**

```bash
git add Makefile
git commit -m "feat: rewrite Makefile with package/push/deploy airgap pipeline"
```

---

## Task 10: 전체 검증

- [ ] **Step 1: Helm 전체 렌더링 — RKE2 기본값**

```bash
helm template kafka-demo ./charts/kafka-demo --debug 2>&1 | grep -E "^---$|image:|imagePullPolicy:" | head -40
```

Expected: 모든 이미지에 `172.16.30.128:5000/` 프리픽스, `pip install` 없음

- [ ] **Step 2: Helm 전체 렌더링 — 로컬 values**

```bash
helm template kafka-demo ./charts/kafka-demo -f charts/kafka-demo/values-local.yaml --debug 2>&1 | grep -E "image:|imagePullPolicy:" | head -40
```

Expected: registry 프리픽스 없음, w1/w2/w3 모두 `pullPolicy: Never`

- [ ] **Step 3: 로컬 배포 smoke test (Kind)**

```bash
make up
```

Kind 클러스터가 없는 경우 생성 → KEDA 설치 → Helm 배포까지 에러 없이 완료되어야 함.

```bash
make status
```

Expected: Pod 상태 Running 확인

- [ ] **Step 4: 최종 커밋**

```bash
git add -A
git status
git commit -m "chore: final cleanup and verification" --allow-empty
```

---

## 스펙 커버리지 체크

| 스펙 항목 | 담당 Task |
|----------|----------|
| 디렉토리 재구조화 | Task 1 |
| hauler v1alpha2 업데이트 | Task 2 |
| 이미지 버전 고정 | Task 2 |
| my-log-service Image 타입 처리 | Task 2, 9 |
| keda manifest 번들 포함 | Task 2 |
| values.yaml RKE2 기본값 | Task 3 |
| values-local.yaml Kind 오버라이드 | Task 4 |
| imagePullPolicy values 반영 | Task 5 |
| kafka-ui global.registry 적용 | Task 6 |
| log-generator pip install 제거 | Task 6 |
| kind-config NodePort 제거 | Task 7 |
| start-local.sh keda 경로 수정 | Task 8 |
| Makefile package/push/deploy | Task 9 |
| make serve 제거 | Task 9 |
