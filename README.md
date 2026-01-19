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

Docker 및 Docker Compose가 설치되어 있어야 합니다.

### 실행 명령어

프로젝트 루트 디렉토리에서 다음 명령어를 실행합니다. Kafka 브로커, Zookeeper, 애플리케이션 컨테이너가 모두 자동으로 실행됩니다.

```bash
# 컨테이너 빌드 및 백그라운드 실행
docker compose up -d --build
```

### 스케일 아웃 (Scale-out) 테스트

특정 서비스(Consumer)의 처리량을 늘리기 위해 인스턴스를 늘리고 싶다면 `--scale` 옵션을 사용합니다.

```bash
# 예: W2 서비스를 3대, W3 서비스를 2대로 확장
docker compose up -d --scale w2-service=3 --scale w3-service=2
```

## 3. 동작 확인

### Kafka UI 접속
*   주소: [http://localhost:8080](http://localhost:8080)

### OpenSearch Dashboards 접속
데이터가 각 인덱스(`w1-logs`, `w2-logs`, `w3-logs`)에 잘 적재되는지 시각적으로 확인할 수 있습니다.
*   주소: [http://localhost:5601](http://localhost:5601)

### 로그 확인
각 서비스가 메시지를 정상적으로 주고받는지 Docker 로그로 확인합니다.

```bash
docker compose logs -f w1-service
docker compose logs -f w2-service
```

## 4. 주요 토픽 및 메시지 구조

| 토픽명 | 설명 | Publisher | Subscriber |
|:---:|:---:|:---:|:---:|
| **`topic-a`** | 원본 로그 데이터 스트림 | `log-generator` | `w1-service` |
| **`topic-b`** | 1차 처리된 문서 ID (분석용) | `w1-service` | `w2-service` |
| **`topic-c`** | 1차 처리된 문서 ID (인덱싱용) | `w1-service` | `w3-service` |

### 메시지 상세 구조

#### 1. `topic-a` (Raw Log)
*   **Value**: `String` (Plain Text)
    ```text
    Log-1704612345-1234
    ```

#### 2. `topic-b`, `topic-c` (Document ID)
*   **Value**: `String` (OpenSearch DocID)
    ```text
    550e8400-e29b-41d4-a716-446655440000
    ```

## 5. 종료

테스트가 끝나면 다음 명령어로 모든 컨테이너와 볼륨을 정리합니다.

```bash
docker compose down -v
```


### 6. k8s 실행 가이드
1. Docker 이미지 빌드
   Kubernetes에서 사용할 수 있도록 애플리케이션 이미지를 먼저 빌드해야 합니다. (로컬 K8s 환경인 경우, 해당 환경의
   Docker Daemon 혹은 레지스트리에 등록되어야 합니다.)

1 # 프로젝트 루트에서 실행
2 docker build -t my-log-service:latest .

2. Kubernetes 리소스 배포
   작성된 파일들을 순서대로 적용합니다. (종속성 관계를 고려한 순서입니다.)

    1 # 1. 네임스페이스 및 설정
    2 kubectl apply -f k8s/00-base.yaml
    3
    4 # 2. 인프라 (Kafka, OpenSearch) - 실행 완료까지 잠시 대기 필요
    5 kubectl apply -f k8s/10-kafka.yaml
    6 kubectl apply -f k8s/20-opensearch.yaml
    7
    8 # 3. 애플리케이션 (W1, W2, W3)
    9 kubectl apply -f k8s/30-app-deployments.yaml
10 kubectl apply -f k8s/40-app-services.yaml

3. 동작 확인 및 테스트
   W1 서비스에 테스트 로그를 전송하여 전체 흐름(W1 -> Kafka -> W2/W3 -> OpenSearch)이 동작하는지 확인합니다.

1 # W1 서비스 포트 포워딩 (로컬 테스트용)
2 kubectl port-forward svc/w1-service 8081:8080 -n kafka-demo &
3
4 # 테스트 로그 발송
5 curl -X POST "http://localhost:8081/api/test/produce?message=K8s-Demo-Log"

4. 로그 및 데이터 확인

1 # 서비스 로그 확인 (W1)
2 kubectl logs -l app=w1-service -n kafka-demo -f
3
4 # OpenSearch 데이터 확인 (OpenSearch 포트 포워딩 필요)
5 kubectl port-forward svc/opensearch 9200:9200 -n kafka-demo &
6 curl -X GET "http://localhost:9200/w1-logs/_search?pretty"

  ---  1. Docker 이미지 빌드
  Kubernetes에서 사용할 수 있도록 애플리케이션 이미지를 먼저 빌드해야 합니다. (로컬 K8s 환경인 경우, 해당 환경의
  Docker Daemon 혹은 레지스트리에 등록되어야 합니다.)

1 # 프로젝트 루트에서 실행
2 docker build -t my-log-service:latest .

2. Kubernetes 리소스 배포
   작성된 파일들을 순서대로 적용합니다. (종속성 관계를 고려한 순서입니다.)

    1 # 1. 네임스페이스 및 설정
    2 kubectl apply -f k8s/00-base.yaml
    3
    4 # 2. 인프라 (Kafka, OpenSearch) - 실행 완료까지 잠시 대기 필요
    5 kubectl apply -f k8s/10-kafka.yaml
    6 kubectl apply -f k8s/20-opensearch.yaml
    7
    8 # 3. 애플리케이션 (W1, W2, W3)
    9 kubectl apply -f k8s/30-app-deployments.yaml
10 kubectl apply -f k8s/40-app-services.yaml

3. 동작 확인 및 테스트
   W1 서비스에 테스트 로그를 전송하여 전체 흐름(W1 -> Kafka -> W2/W3 -> OpenSearch)이 동작하는지 확인합니다.

1 # W1 서비스 포트 포워딩 (로컬 테스트용)
2 kubectl port-forward svc/w1-service 8081:8080 -n kafka-demo &
3
4 # 테스트 로그 발송
5 curl -X POST "http://localhost:8081/api/test/produce?message=K8s-Demo-Log"

4. 로그 및 데이터 확인

1 # 서비스 로그 확인 (W1)
2 kubectl logs -l app=w1-service -n kafka-demo -f
3
4 # OpenSearch 데이터 확인 (OpenSearch 포트 포워딩 필요)
5 kubectl port-forward svc/opensearch 9200:9200 -n kafka-demo &
6 curl -X GET "http://localhost:9200/w1-logs/_search?pretty"
