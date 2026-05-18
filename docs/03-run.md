# 03. Run — systemd 등록 + 검증

> 자동: `./run.sh start && ./run.sh smoke`

## 3.1 systemd unit

`config/ords.service.tmpl` 의 변수들을 `envsubst` 로 치환해 `/etc/systemd/system/ords.service` 로 배치:

```ini
[Unit]
Description=Oracle REST Data Services (ORDS)
After=network.target

[Service]
Type=simple
User=oracle
Environment=JAVA_HOME=/opt/java/current
Environment=PATH=/opt/java/current/bin:/usr/bin:/bin
ExecStart=/opt/oracle/ords/current/bin/ords --config /etc/ords/config serve --port 8080
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

수동 등록:
```bash
sudo systemctl daemon-reload
sudo systemctl enable ords
sudo systemctl start ords
```

## 3.2 상태 / 로그

```bash
sudo systemctl status ords
sudo journalctl -u ords -f               # 실시간
sudo journalctl -u ords -n 100 --no-pager
ls /etc/ords/config/logs/                # ORDS 자체 로그
```

## 3.3 smoke test

```bash
curl -sf http://localhost:8080/ords/_/landing | head
```

SQL 검증 (sqlcl):
```bash
/opt/oracle/sqlcl/bin/sql /nolog <<EOF
connect ADMIN/"$ADMIN_PASSWORD"@myadb_high
@sql/smoke_test.sql
exit
EOF
```

`smoke_test.sql` 이 출력하는 것:
- `ORDS_METADATA`, `ORDS_PUBLIC_USER` 계정 상태
- ORDS 설치 버전 (`ords.installed_version`)
- enable 된 스키마 목록
- 풀 통계 (`v$ords_pool_stats`)

## 3.4 흔한 문제

| 증상 | 원인 |
|---|---|
| `Address already in use` | 8080 이미 사용 중 — `.env` 에서 `ORDS_PORT` 변경 |
| `IO Error: Network Adapter could not establish` | wallet 경로 / `TNS_ADMIN` 미설정 / VCN egress 막힘 |
| `ORA-01017 invalid username/password` | `ADMIN_PASSWORD` 오타, ADB 콘솔에서 reset |
| `systemd` 가 즉시 죽음 | `journalctl -u ords -n 50` — JAVA_HOME symlink 깨졌을 가능성 |
