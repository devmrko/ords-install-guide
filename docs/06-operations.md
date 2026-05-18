# 06. 운영 — 백업, 모니터링, 로그 회전, 인증서 자동갱신

설치 직후엔 동작만 확인하면 되지만, 운영으로 넘어가기 전 최소한 이 4가지는 박아두세요.

## 6.1 백업 / 복구

### 백업 대상

| 대상 | 위치 | 빈도 | RPO/RTO 기준 |
|---|---|---|---|
| ORDS config | `/etc/ords/config/` | 일 1회 + 변경 시 즉시 | RPO 1d / RTO 30m |
| systemd unit | `/etc/systemd/system/ords.service` | 변경 시 즉시 | — |
| wallet | `/opt/oracle/wallet/`, `/opt/oracle/wallet.zip` | wallet rotation 시 | 영구 보관 |
| terraform state | `terraform/terraform.tfstate` 또는 원격 backend | apply 마다 | versioned 보관 |
| 사설 cert PEM | `/etc/ords/tls/` | 갱신 시 | 보안 보관 (Vault 권장) |

> ADB 자체는 OCI 자동 백업으로 커버됨 — 이 cookbook 범위 밖.

### 백업 스크립트 예 (cron)

```bash
#!/usr/bin/env bash
# /usr/local/sbin/ords-backup.sh — 매일 02:00 cron
set -euo pipefail
DEST=/var/backups/ords/$(date +%F)
mkdir -p "$DEST"
tar -czf "$DEST/ords-config.tgz" -C / etc/ords/config
cp /etc/systemd/system/ords.service "$DEST/"
# wallet 은 보안 위해 별도 보호된 경로(예: OCI Vault, 사내 키관리)로
# 30일 이전 백업 제거
find /var/backups/ords -maxdepth 1 -type d -mtime +30 -exec rm -rf {} +
```

cron:
```
0 2 * * * /usr/local/sbin/ords-backup.sh >> /var/log/ords-backup.log 2>&1
```

### 복구 리허설

```bash
# 신규 노드에서:
./run.sh prereq install
sudo tar -xzf /backup/ords-config.tgz -C /
sudo cp /backup/ords.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now ords
./run.sh smoke
```
분기 1회 이상 실제 복구 리허설 권장 (백업이 살아있는지 검증).

## 6.2 모니터링 / 알림

### 권장 지표 (SLI)

| 지표 | 측정 방법 | 임계치 (예) |
|---|---|---|
| LB healthcheck 실패율 | LB metrics → `HealthyBackendCount` | 1개 노드라도 5분 연속 unhealthy → alert |
| HTTP 5xx 비율 | LB metrics → `HttpResponses5xx` / total | 5분 5% 초과 → warning, 10% → critical |
| JVM heap | JMS / JFR / Prometheus JMX exporter | used / max > 85% 10분 연속 |
| ORDS DB pool 포화 | `select * from v$ords_pool_stats` | `in_use / max_size > 0.9` |
| Wallet 만료 | ADB wallet 의 cert 만료일 | 30일 이전 알림 |
| LB cert 만료 | OCI Certificate Service → `notAfter` | 30일 이전 알림 (OCI 자체 알림 사용) |

### OCI 통합

- **OCI Monitoring**: LB / Compute / Network 메트릭 자동 수집
- **OCI Logging**: systemd journal + `/etc/ords/config/logs/` 수집하려면 Unified Monitoring Agent 설치
- **OCI Notifications**: 위 임계치 → 이메일/Slack/PagerDuty

### 간단 health probe (외부)

```bash
# 외부 모니터링(예: UptimeRobot, Datadog)에서:
curl -fsS --max-time 5 https://<LB_HOST>/ords/_/landing
# 실패 시 즉시 알림
```

## 6.3 로그 회전 (logrotate)

ORDS 자체 로그가 회전 없이 쌓이면 디스크 고갈 위험.

`/etc/logrotate.d/ords`:
```
/etc/ords/config/logs/*.log {
    daily
    rotate 14
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    create 0640 oracle oinstall
    su oracle oinstall
}

/var/log/ords-backup.log {
    weekly
    rotate 8
    compress
    notifempty
    missingok
}
```

검증:
```bash
sudo logrotate -d /etc/logrotate.d/ords    # dry-run
sudo logrotate -f /etc/logrotate.d/ords    # 강제 1회
```

systemd journal 은 별도:
```bash
# /etc/systemd/journald.conf 또는 drop-in
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/ords.conf <<EOF
[Journal]
SystemMaxUse=2G
MaxRetentionSec=30day
EOF
sudo systemctl restart systemd-journald
```

## 6.4 인증서 자동 갱신 (cron + 안전 가드)

`05-cert-from-oci.md` §5.6 의 단순 cron 은 위험 (실패해도 systemd restart 강행).
안전 버전:

`/usr/local/sbin/ords-cert-refresh.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
REPO=/opt/ords-install-guide
LOCK=/var/lock/ords-cert-refresh.lock
LOG=$REPO/logs/cert-refresh-$(date +%Y%m%d).log

# 1) 동시 실행 차단
exec 9>"$LOCK"
flock -n 9 || { echo "already running"; exit 0; }

cd "$REPO"

# 2) 새 PEM 받기 (실패하면 즉시 종료, 기존 파일 손상 안 시킴)
if ! ./run.sh fetch-cert >>"$LOG" 2>&1; then
  echo "fetch failed — keeping previous cert" | tee -a "$LOG"
  exit 1
fi

# 3) PEM 유효성 검증
source ./.env
if ! openssl x509 -in "$TLS_CERT_PEM" -noout -checkend 0 >/dev/null 2>&1; then
  echo "fetched cert is expired or invalid — abort restart" | tee -a "$LOG"
  exit 1
fi

# 4) cert/key 매칭 검증 (직접 HTTPS 종단인 경우만)
if [[ -f "$TLS_KEY_PEM" ]]; then
  CERT_MOD=$(openssl x509 -noout -modulus -in "$TLS_CERT_PEM" | openssl md5)
  KEY_MOD=$( openssl rsa  -noout -modulus -in "$TLS_KEY_PEM"  | openssl md5)
  [[ "$CERT_MOD" == "$KEY_MOD" ]] || { echo "cert/key modulus mismatch — abort"; exit 1; }
fi

# 5) ORDS 직접 종단인 경우만 restart (LB 종단이면 restart 불필요)
if grep -q 'standalone.https.cert' /etc/ords/config/databases/default/pool.xml 2>/dev/null; then
  systemctl reload-or-restart ords
  sleep 5
  if ! curl -fsS --max-time 5 https://localhost:${ORDS_PORT:-8443}/ords/_/landing >/dev/null; then
    echo "restart succeeded but healthcheck failed — manual intervention" | tee -a "$LOG"
    exit 1
  fi
fi

echo "$(date) — cert refreshed OK" | tee -a "$LOG"
```

cron:
```
0 3 * * * /usr/local/sbin/ords-cert-refresh.sh
```

핵심:
- `flock` 으로 동시 실행 차단
- fetch 실패 시 기존 cert 유지 (덮어쓰지 않음)
- openssl 로 cert 만료/유효성 검증
- cert/key modulus 비교로 mismatch 차단
- 직접 HTTPS 종단인 경우만 restart, 그 후 healthcheck 확인 후 성공 처리
