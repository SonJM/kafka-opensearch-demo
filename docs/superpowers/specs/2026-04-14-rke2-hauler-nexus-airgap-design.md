# Air-gap 배포 파이프라인 설계 (RKE2 + Hauler + Nexus)

**날짜:** 2026-04-14  
**브랜치:** k8s-kafka  
**작성자:** SonJM

---

## 1. 배경 및 목표

### 현재 상태
- Kafka KRaft 기반 데모 애플리케이션 (Spring Boot + KEDA 오토스케일링)
- 로컬 테스트: Kind 클러스터 + Helm
- 패키징: Hauler (`v1alpha1`, deprecated)
- 이미지 관리: 폐쇄망 내 Nexus (172.16.30.128:5000)에 Docker hosted registry 운영 중

### 최종 목표
1. 인터넷이 연결된 Dev PC에서 단일 번들(`.tar.zst`) 생성
2. 번들을 폐쇄망으로 이전하여 Nexus에 push
3. RKE2 클러스터가 Nexus에서 이미지를 pull하여 Helm으로 배포
4. 수동 스크립트 → 추후 Jenkins CD 파이프라인으로 확장

---

## 2. 환경 정의

### 2-1. 로컬 환경 (Kind)
| 항목 | 값 |
|------|-----|
| 목적 | 개발/테스트 |
| 클러스터 | Kind (`kafka-demo`) |
| 이미지 pull | `imagePullPolicy: Never` (kind load로 직접 주입) |
| Registry | 없음 (`global.registry: ""`) |
| Values | `charts/kafka-demo/values-local.yaml` override 사용 |

### 2-2. 배포 환경 (RKE2)
| 항목 | 값 |
|------|-----|
| 목적 | 개발서버 (단일 노드) / 고객사 납품 (멀티 노드) |
| 클러스터 | RKE2 |
| 이미지 pull | Nexus Docker registry (`172.16.30.128:5000`) |
| Registry | `global.registry: 172.16.30.128:5000` |
| Values | `charts/kafka-demo/values.yaml` (기본값) |
| Nexus UI | `http://172.16.30.128:8081` |
| Nexus Docker | `http://172.16.30.128:5000` |

---

## 3. 디렉토리 구조

```
kafka-demo/
├── charts/
│   └── kafka-demo/
│       ├── Chart.yaml
│       ├── values.yaml            # RKE2 기본값 (global.registry 포함)
│       ├── values-local.yaml      # Kind 오버라이드
│       └── templates/
│           ├── 00-base.yaml       # ConfigMap
│           ├── 10-kafka.yaml      # Kafka StatefulSet (KRaft)
│           ├── 20-opensearch.yaml # OpenSearch
│           ├── 30-apps.yaml       # W1/W2/W3 Deployment
│           ├── 50-tools.yaml      # kafka-ui, log-generator, init-topics Job
│           └── 70-keda.yaml       # KEDA ScaledObjects
├── deploy/
│   ├── airgap/
│   │   └── hauler.yaml            # Hauler BOM (v1alpha2)
│   └── kind/
│       └── kind-config.yaml       # Kind 클러스터 설정
├── docs/
│   └── superpowers/specs/
│       └── 2026-04-14-rke2-hauler-nexus-airgap-design.md
├── scripts/
│   ├── start-local.sh             # Kind 환경 시작 (make up)
│   └── check-status.sh            # 상태 확인 (make status)
├── Makefile
├── Dockerfile
└── src/                           # Spring Boot 애플리케이션
```

### 삭제 대상
| 경로 | 사유 |
|------|------|
| `scripts/start-kind.sh` | `start-local.sh`와 중복 |
| `deploy/k8s/*.yaml` (전체) | Helm chart로 완전히 대체됨 |

---

## 4. 배포 플로우

### 4-1. 패키징 플로우 (Dev PC — 인터넷 연결)

```
make package
  1. docker build -t my-log-service:latest .
  2. hauler store sync -f deploy/airgap/hauler.yaml
       └── 외부 이미지/파일/chart pull (인터넷 필요)
  3. hauler store add image my-log-service:latest
       └── 로컬 빌드 이미지를 Image 타입으로 추가
           (File 타입으로 추가 시 Nexus push 불가)
  4. hauler store save --filename kafka-demo-airgap.tar.zst
  
  → 산출물: kafka-demo-airgap.tar.zst (단일 번들)
```

> **참고:** `my-log-service`는 공개 registry에서 pull할 수 없으므로 `hauler.yaml`의 Images 목록에서 제외하고, 빌드 후 `hauler store add image`로 직접 주입한다.

### 4-2. 번들 전송
```
scp kafka-demo-airgap.tar.zst user@172.16.30.128:/opt/airgap/
```
또는 USB 매체 물리 이전.

### 4-3. Nexus Push (폐쇄망 서버)

```
make push
  1. hauler store load kafka-demo-airgap.tar.zst
  2. hauler store copy registry://172.16.30.128:5000
       └── hauler store에서 Nexus Docker registry로 이미지 복사
  
  → Nexus Docker hosted repository에 이미지 적재 완료
```

> **참고:** `hauler store serve registry`는 hauler 자체를 레지스트리로 노출하는 명령(RKE2가 hauler에서 직접 pull할 때 사용)이며, Nexus로 push하는 명령은 `hauler store copy registry://`이다.

### 4-4. RKE2 배포

```
make deploy
  helm upgrade --install kafka-demo ./charts/kafka-demo \
    --namespace kafka-demo \
    --create-namespace \
    --set global.registry=172.16.30.128:5000
  
  → RKE2 노드가 Nexus(172.16.30.128:5000)에서 이미지 pull
```

---

## 5. Hauler BOM 설계 (`deploy/airgap/hauler.yaml`)

### apiVersion 변경
```yaml
# 변경 전 (deprecated)
apiVersion: content.hauler.cattle.io/v1alpha1

# 변경 후
apiVersion: content.hauler.cattle.io/v1alpha2
```

### 번들 구성 목록

**Files** (바이너리/매니페스트):
- `rke2-install.sh` — RKE2 설치 스크립트
- `rke2.linux-amd64.tar.gz` — RKE2 바이너리
- `rke2-images.linux-amd64.tar.zst` — RKE2 컨테이너 이미지
- `helm-v3.13.2.tar.gz` — Helm 바이너리
- `k9s.tar.gz` — k9s 바이너리
- `keda-2.12.0.yaml` — KEDA 설치 매니페스트

**Images** (컨테이너 이미지, 버전 고정):
- `apache/kafka:4.1.1`
- `opensearchproject/opensearch:2.11.1`
- `provectuslabs/kafka-ui:v0.7.2` (latest → 버전 고정)
- `ghcr.io/kedacore/keda:2.12.0`
- `ghcr.io/kedacore/keda-metrics-apiserver:2.12.0`
- `ghcr.io/kedacore/keda-admission-webhooks:2.12.0`
- `busybox:1.36` (latest → 버전 고정)
- `my-log-service:latest` — **hauler.yaml 제외, make package에서 직접 추가**

**Charts**:
- `kafka-demo` — 로컬 차트 패키지 (`./charts/kafka-demo`)

---

## 6. Helm Chart 수정 사항

### 6-1. `values.yaml` (RKE2 기본값)

```yaml
global:
  registry: "172.16.30.128:5000"  # RKE2 기본값
  environment: production

kafkaUI:
  image:
    repository: provectuslabs/kafka-ui
    tag: "v0.7.2"

logGenerator:
  image:
    repository: apache/kafka   # python:3.9-slim 대체
    tag: 4.1.1
  enabled: true
```

### 6-2. `values-local.yaml` (Kind 오버라이드)

```yaml
global:
  registry: ""          # registry 없음 (kind load로 주입)
  environment: local

kafka:
  storage: 100Mi        # 로컬용 축소

# imagePullPolicy: Never — kind load된 이미지 사용
```

### 6-3. `50-tools.yaml` 수정

**kafka-ui** — `global.registry` 적용:
```yaml
image: "{{ if .Values.global.registry }}{{ .Values.global.registry }}/{{ end }}{{ .Values.kafkaUI.image.repository }}:{{ .Values.kafkaUI.image.tag }}"
```

**log-generator** — `pip install` 제거, kafka 이미지의 console-producer 활용:
```yaml
image: "{{ if .Values.global.registry }}{{ .Values.global.registry }}/{{ end }}{{ .Values.logGenerator.image.repository }}:{{ .Values.logGenerator.image.tag }}"
command: ["/bin/bash", "-c"]
args:
  - |
    while true; do
      echo "Log entry $(date)" | \
        /opt/kafka/bin/kafka-console-producer.sh \
          --bootstrap-server kafka-headless:9092 \
          --topic topic-a
      sleep 1
    done
```

### 6-4. `kind-config.yaml` 수정

NodePort 매핑(30080/30081) 제거. 로컬 접근은 `make proxy`(port-forward)로 통일.

---

## 7. Makefile 타겟 정의

| 타겟 | 환경 | 역할 |
|------|------|------|
| `make up` | 로컬(Kind) | Kind 클러스터 생성 + KEDA 설치 + Helm 배포 |
| `make down` | 로컬(Kind) | Helm release 제거 |
| `make clean` | 로컬(Kind) | Kind 클러스터 삭제 |
| `make proxy` | 로컬(Kind) | port-forward (kafka-ui:8090, opensearch:9200) |
| `make status` | 공통 | 클러스터 상태 확인 |
| `make logs` | 공통 | 앱 로그 tail |
| `make hmac` | 공통 | HMAC 스크립트 실행 |
| `make k9s` | 공통 | k9s 실행 |
| `make package` | Dev PC | 이미지 빌드 + hauler sync + bundle 저장 |
| `make push` | 폐쇄망 서버 | bundle load + Nexus push |
| `make deploy` | RKE2 | helm upgrade (Nexus registry) |

**제거:** `make serve` (→ `make push`로 대체)

---

## 8. Jenkins 전환 계획 (추후)

현재 수동 스크립트 구조는 Jenkins로 자연스럽게 확장된다:

```
[Jenkins Pipeline]
Stage 1: Build    → docker build + hauler store add image
Stage 2: Package  → hauler store sync + save
Stage 3: Transfer → scp to air-gap server (or artifact store)
Stage 4: Push     → hauler store load + serve (Nexus push)
Stage 5: Deploy   → helm upgrade --install
```

각 `make` 타겟이 Jenkins stage 1:1 대응되도록 스크립트를 설계한다.

---

## 9. 미결 사항

| 항목 | 내용 |
|------|------|
| Nexus Helm repository | Docker hosted 외 Helm hosted repo 추가 필요 (포트 TBD) |
| RKE2 imagePullSecret | Nexus 인증이 필요한 경우 K8s Secret + `imagePullSecrets` 설정 |
| 멀티 노드 구성 | 고객사 납품 시 RKE2 HA(3 control-plane) 구성 별도 설계 |
| Hauler v1alpha2 정확한 스펙 | 실제 명령 실행 시 `hauler --help`로 최신 문법 확인 |
