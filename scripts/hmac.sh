Bash
#!/bin/bash

# 1. 서비스별 경로 설정 (모두 20260203으로 변경)
TARGETS=(
    "/data/blackbox/loader/application/chansik/backup/save/20260203/09|/data/blackbox/loader/application/chansik/wlogs"
    "/data/blackbox/loader/application/test/backup/save/20260203/09|/data/blackbox/loader/application/test/wlogs"
    "/data/blackbox/loader/application/demo1112/backup/save/20260203/09|/data/blackbox/loader/application/demo1112/wlogs"
    "/data/blackbox/loader/application/yuntest/backup/save/20260203/09|/data/blackbox/loader/application/yuntest/wlogs"
)

# 2. 삭제할 인덱스 리스트 (2026-02-03으로 변경)
DELETE_INDICES=(
    "wbsr-2026-02-03"
    "wbshmac-2026-02-03"
)

echo "[$(date)] 스크립트 가동 시작 (모든 서비스 20260203 데이터 동시 이동)"

while true
do
    echo "===================================================="
    echo "[$(date)] [STEP 1] 4개 서비스 데이터 동시 이동 개시 (20260203/09)"

    # 모든 이동 작업을 백그라운드(&)로 실행하여 "동시"에 시작
    for entry in "${TARGETS[@]}"; do
        (
            SRC_DIR="${entry%|*}"
            DST_DIR="${entry#*|}"

            if [ "$(ls -A "$SRC_DIR" 2>/dev/null)" ]; then
                echo "[$(date)] [시작] 이동 명령 전송: $SRC_DIR"
                mv "$SRC_DIR"/* "$DST_DIR"/
                echo "[$(date)] [완료] 이동 완료: $SRC_DIR"
            else
                echo "[$(date)] [알림] 경로 없음 또는 파일 없음: $SRC_DIR"
            fi
        ) & 
    done

    # 4개의 백그라운드 작업이 모두 끝날 때까지 대기
    wait
    echo "[$(date)] 모든 서비스의 파일 이동 작업이 종료되었습니다."

    # 3. 1시간(3600초) 대기
    echo "----------------------------------------------------"
    echo "[$(date)] [STEP 2] 데이터 처리를 위해 1시간 대기 시작..."
    sleep 3600

    # 4. 인덱스 삭제
    echo "[$(date)] [STEP 3] 오픈서치 인덱스 삭제 시작"
    for idx in "${DELETE_INDICES[@]}"; do
        echo "[$(date)] 삭제 대상: $idx"
        curl -XDELETE "http://localhost:9200/$idx"
        echo -e "\n"
    done
    
    echo "[$(date)] 사이클 종료. 다시 시작 대기 중..."
    echo "===================================================="
done