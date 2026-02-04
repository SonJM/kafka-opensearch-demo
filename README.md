# Kafka Demo Project

이 프로젝트는 **Spring Boot**와 **Kafka**, **OpenSearch**를 활용하여 대규모 로그 수집 및 분산 처리 파이프라인을 구축한 데모입니다.
Kafka의 동작 원리(Producer/Consumer, Consumer Group)와 Docker Compose를 이용한 MSA 환경 구축 방법을 학습하기 위해 작성되었습니다.

## 1. 프로젝트 개요

*   **목적**: Kafka 기반의 비동기 메시지 처리 및 마이크로서비스 간 데이터 흐름 검증.
*   **핵심 기술**:
    *   **Language/Framework**: Java 17, Spring Boot 3.x
    *   **Infrastructure**: Apache Kafka, Zookeeper, OpenSearch, OpenSearch Dashboards
    *   **Tool**: Docker, Docker Compose, Kafka UI

### 시스템 아키텍처 흐름 (Data Pipeline)
1.  **Log Generator**: 1초마다 임의의 로그 메시지를 생성하여 `topic-a`로 발행.
2.  **Service W1 (Ingestion)**: 
    *   `topic-a` 구독 및 로그 수신.
    *   **OpenSearch 적재**: `w1-logs` 인덱스에 데이터 저장.
    *   생성된 `DocID`를 `topic-b`, `topic-c`로 전파.
3.  **Service W2 (Analysis)**: 
    *   `topic-b` 구독 (DocID 수신).
    *   **Re-indexing**: `w1-logs`에서 데이터 원본 조회 후 `w2-logs` 인덱스에 동일한 ID로 적재.
4.  **Service W3 (Indexing)**: 
    *   `topic-c` 구독 (DocID 수신).
    *   **Re-indexing**: `w1-logs`에서 데이터 원본 조회 후 `w3-logs` 인덱스에 동일한 ID로 적재.

## 2. 환경 구축 및 실행

### 방법 A: Docker Compose (빠른 데모)
Kafka 브로커, OpenSearch, 앱 컨테이너를 로컬 Docker 환경에서 즉시 실행합니다.
```bash
docker compose up -d --build
```

### 방법 B: Kubernetes (Kind + Helm) - 추천 ⭐
로컬 Kubernetes 클러스터(Kind)를 생성하고 KEDA, Helm 차트를 포함한 전체 스택을 배포합니다. 루트에 있는 `Makefile`을 통해 모든 과정을 자동화했습니다.

```bash
# 1. 전체 환경 자동 구축 (Cluster 생성 + 이미지 빌드/로드 + Helm 배포)
make up

# 2. 클러스터 및 Pod 상태 확인
make status

# 3. 실시간 모니터링 (k9s 실행)
make k9s

# 4. 환경 삭제
make clean
```

---

## 3. 주요 관리 명령어 (Makefile)

| 명령어 | 설명 |
|:---:|:---|
| `make up` | Kind 클러스터 생성 및 전체 서비스 배포 (`scripts/start-local.sh`) |
| `make status` | 현재 클러스터, 컨텍스트, 헬름 릴리즈 상태 진단 |
| `make logs` | 주요 애플리케이션 로그 실시간 확인 |
| `make k9s` | k9s 모니터링 툴 실행 (설치 필요) |
| `make clean` | 생성된 Kind 클러스터 및 관련 리소스 완전 삭제 |
| `make hmac` | HMAC 데이터 이동 및 인덱스 관리 스크립트 실행 |

---

## 4. 디렉토리 구조 정리

```text
.
├── deploy/             # Kubernetes 인프라 설정
│   ├── k8s/            # 정적 매니페스트 및 KEDA 설정
│   └── kind/           # Kind 클러스터 및 Hauler 설정
├── charts/             # Helm Charts (메인 배포 소스)
├── scripts/            # 운영 및 자동화 스크립트
├── src/                # 애플리케이션 소스 코드
├── Dockerfile          # 앱 이미지 빌드 설정
├── Makefile            # 통합 커맨드 센터 (Entry point)
└── docker-compose.yml  # 로컬 데모용 설정
```

---

## 5. On-Premise Air-gapped Deployment (Hauler)

인터넷이 차단된 고객사 폐쇄망 환경에서 **Hauler**를 이용해 전체 아티팩트를 패키징하고 배포하는 절차입니다.

### 5.1 패키징 (외부망 / 개발자 PC)

1. **애플리케이션 이미지 빌드 및 저장**
   ```bash
   docker build -t my-log-service:latest .
   docker save my-log-service:latest -o my-log-service.tar
   ```

2. **Hauler 저장소 동기화 (Sync)**
   `deploy/kind/hauler.yaml`에 정의된 리소스를 동기화합니다.
   ```bash
   hauler store add file my-log-service.tar
   hauler store sync -f deploy/kind/hauler.yaml
   ```

3. **아티팩트 내보내기 (Save)**
   ```bash
   hauler store save --filename kafka-demo-airgap.tar.zst
   ```

### 5.2 배포 (폐쇄망 / 고객사 서버)

전송된 아티팩트를 사용하여 로컬 레지스트리를 구동하고 배포합니다.

```bash
# 1. 로컬 레지스트리/파일 서버 구동
hauler store serve registry -p 5000 --files-port 8080 kafka-demo-airgap.tar.zst &

# 2. Helm 배포
helm install kafka-demo oci://localhost:5000/kafka-demo-charts/kafka-demo \
  --version 0.1.0 \
  --set global.registry="localhost:5000/" \
  --namespace kafka-demo --create-namespace
```