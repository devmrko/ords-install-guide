# 02. Configure — pool 생성 + ADB 연결

> 자동: `./run.sh configure`

## 2.1 wallet 배치

ADB 콘솔에서 wallet zip 다운로드 → 노드에 풀어두기:
```bash
sudo mkdir -p /opt/oracle/wallet
sudo unzip -q ~/wallet_MYADB.zip -d /opt/oracle/wallet
sudo chown -R oracle:oinstall /opt/oracle/wallet
```

확인:
```bash
ls /opt/oracle/wallet/
# cwallet.sso  ewallet.p12  tnsnames.ora  sqlnet.ora  ...
grep -i myadb /opt/oracle/wallet/tnsnames.ora
# myadb_high = (description = ...)
# myadb_medium = (description = ...)
# myadb_low = (description = ...)
```

`.env` 에:
```bash
WALLET_PATH=/opt/oracle/wallet
ADB_TNS=myadb_high          # 워크로드에 맞춰 high/medium/low 선택
```

## 2.2 `ords install` 실행

대화형 회피 + idempotent 하게:
```bash
export TNS_ADMIN=/opt/oracle/wallet
sudo -E /opt/oracle/ords/current/bin/ords \
  --config /etc/ords/config \
  install \
  --admin-user ADMIN \
  --db-pool default \
  --feature-db-api true \
  --feature-rest-enabled-sql true \
  --log-folder /etc/ords/config/logs \
  --db-wallet-zip-path /opt/oracle/wallet \
  --db-tns-alias myadb_high \
  --jdbc-init-limit 5 \
  --jdbc-max-limit 25 \
  --password-stdin <<EOF
$ADMIN_PASSWORD
$ORDS_PUBLIC_USER_PASSWORD
EOF
```

생성되는 것:
- `/etc/ords/config/databases/default/pool.xml`
- `ORDS_METADATA`, `ORDS_PUBLIC_USER` 스키마 (DB 측)

## 2.3 풀(pool) 사이즈 산정

```
(JDBC_MAX_LIMIT × 노드 수)  ≤  ADB sessions 한도
```
ADB 의 sessions 한도는 워크로드별로 다름 — `select value from v$parameter where name='sessions'` 로 확인.
2노드 × 25 = 50 세션이면 ADB 19c Always Free(20) 같은 작은 인스턴스는 초과.

## 2.4 검증

```bash
ls /etc/ords/config/databases/default/
# pool.xml  wallet/  ...
sudo cat /etc/ords/config/databases/default/pool.xml
```
