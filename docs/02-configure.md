# 02. Configure — pool 생성 + ADB 연결

> 자동: `./run.sh configure`
> ORDS 24.x CLI 기준 — `ords install adb` 서브커맨드 사용.

## 2.1 wallet 배치

ADB 콘솔에서 wallet zip 다운로드 → 노드에 풀어두기:
```bash
sudo mkdir -p /opt/oracle/wallet
sudo unzip -q ~/wallet_MYADB.zip -d /opt/oracle/wallet
sudo chown -R oracle:oinstall /opt/oracle/wallet

# zip 원본도 보관 (ords install adb --wallet 가 zip 을 요구)
sudo cp ~/wallet_MYADB.zip /opt/oracle/wallet.zip
sudo chmod 600 /opt/oracle/wallet.zip
```

확인:
```bash
ls /opt/oracle/wallet/
# cwallet.sso  ewallet.p12  tnsnames.ora  sqlnet.ora  ...
grep -i myadb /opt/oracle/wallet/tnsnames.ora
# myadb_high   = (description = ...)
# myadb_medium = (description = ...)
# myadb_low    = (description = ...)
```

`.env` 에:
```bash
WALLET_PATH=/opt/oracle/wallet         # 풀린 디렉토리 (TNS_ADMIN 용)
WALLET_ZIP=/opt/oracle/wallet.zip      # zip 원본 (ords install --wallet 가 요구)
ADB_TNS=myadb_high                     # high/medium/low — 워크로드에 따라
```

> `WALLET_ZIP` 을 비우면 `02_configure.sh` 가 자동으로 `WALLET_PATH` 를
> 압축해서 zip 을 만듭니다. (`zip` 명령 필요)

## 2.2 `ords install adb` 실행

```bash
export TNS_ADMIN=/opt/oracle/wallet
sudo -E /opt/oracle/ords/current/bin/ords \
  --config /etc/ords/config \
  install adb \
  --admin-user ADMIN \
  --db-user ORDS_PUBLIC_USER2 \
  --gateway-user ORDS_PLSQL_GATEWAY2 \
  --db-pool default \
  --wallet /opt/oracle/wallet.zip \
  --wallet-service-name myadb_high \
  --feature-sdw true \
  --feature-db-api true \
  --feature-rest-enabled-sql true \
  --jdbc-init-limit 5 \
  --jdbc-max-limit 25 \
  --log-folder /etc/ords/config/logs \
  --password-stdin <<EOF
$ADMIN_PASSWORD
$ORDS_DB_USER_PASSWORD
$ORDS_GATEWAY_USER_PASSWORD
EOF
```

비밀번호는 stdin 으로 **3개 순서** 입력:
1. ADMIN 비밀번호
2. ORDS_DB_USER (런타임) 비밀번호
3. ORDS_GATEWAY_USER (PL/SQL gateway) 비밀번호

> 왜 ORDS_PUBLIC_USER**2** / ORDS_PLSQL_GATEWAY**2** 인가?
> ORDS 24.x 가 기본 사용자명 충돌 회피용으로 권장하는 패턴.
> 기존에 ORDS_PUBLIC_USER 가 있으면 새 deployment 용으로 분리.

생성되는 것:
- `/etc/ords/config/databases/default/pool.xml`
- `ADMIN` (이미 있음), `ORDS_METADATA`, `ORDS_DB_USER`, `ORDS_GATEWAY_USER` 4개 계정

## 2.3 풀(pool) 사이즈 산정

```
(JDBC_MAX_LIMIT × 노드 수) × (1 + 운영 headroom) + 비ORDS 세션  ≤  ADB sessions 한도
```

예시:
- 2노드 × 25 = 50 ORDS 세션
- headroom 30% → 65
- 백업/배치/모니터링 세션 +20 → **85 세션 예상**
- ADB sessions 한도가 100 이면 OK, 50 이면 위험

ADB 한도 확인:
```sql
select name, value from v$parameter where name = 'sessions';
```

## 2.4 검증

```bash
ls /etc/ords/config/databases/default/
# pool.xml  wallet/  ...
sudo cat /etc/ords/config/databases/default/pool.xml
# db.username, db.connectionType=tns, wallet.service.name 확인
```
