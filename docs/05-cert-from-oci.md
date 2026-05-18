# 05. OCI Certificate Service 인증서를 OS 에서 사용하기

> 자동: `./run.sh fetch-cert`
>
> **시나리오**: 인증서를 OCI Certificate Service 에서 발급/관리하고 있고,
> 이걸 ORDS 노드 OS 에 내려받아 등록해야 하는 경우.
>
> - LB 가 TLS 종단하면 LB 만 cert 알면 됨 → 이 문서 불필요
> - 그러나 **ORDS 가 직접 HTTPS 종단**하거나, **end-to-end TLS** (LB → ORDS 도 HTTPS),
>   또는 **OS 의 curl/openssl/java 가 OCI 발급 cert 를 신뢰**해야 한다면 필요

---

## 5.1 사전조건

- `oci` CLI 설치 + `oci setup config` 완료
- `jq` 설치 (`yum install -y jq` / `apt install -y jq`)
- IAM 정책: 해당 컴파트먼트의 `CERTIFICATE_READ` + `CERTIFICATE_BUNDLE_READ`
  ```
  allow group ords-admins to read certificates in compartment <name>
  allow group ords-admins to read certificate-bundles in compartment <name>
  ```
- `.env` 에 `OCI_CERT_OCID` 채워둠

## 5.2 가져오는 방법 (OCI CLI)

```bash
oci certificates certificate-bundle get \
  --certificate-id "$OCI_CERT_OCID" \
  --bundle-type CERTIFICATE_CONTENT_WITH_PRIVATE_KEY \
  --output json > /tmp/bundle.json

jq -r '.data."certificate-pem"' /tmp/bundle.json > /etc/ords/tls/cert.pem
jq -r '.data."private-key-pem"' /tmp/bundle.json > /etc/ords/tls/privkey.pem
jq -r '.data."cert-chain-pem"'  /tmp/bundle.json > /etc/ords/tls/chain.pem
chmod 600 /etc/ords/tls/privkey.pem
chown oracle:oinstall /etc/ords/tls/*.pem
```

bundle-type 종류:
- `CERTIFICATE_CONTENT_PUBLIC_ONLY` — public cert + chain (개인키 X)
- `CERTIFICATE_CONTENT_WITH_PRIVATE_KEY` — 위 + 개인키 **(OCI 가 관리하는 키는 export 불가, IMPORTED 만 가능)**

> ⚠️ **중요**: OCI 가 자체 생성한 키는 export 불가. 즉 "OCI Internal CA 발급" cert 는
> 개인키가 OCI 밖으로 안 나옴 → ORDS 가 직접 HTTPS 종단 못 함.
> 이 경우엔 **LB 종단 방식** 또는 **IMPORTED cert** 로 전환해야 함.

## 5.3 OS truststore 등록 (chain을 시스템 CA로 신뢰)

### RHEL / Oracle Linux
```bash
sudo cp /etc/ords/tls/chain.pem /etc/pki/ca-trust/source/anchors/ords-oci-chain.pem
sudo update-ca-trust extract
```
검증:
```bash
trust list --filter=ca-anchors | grep -A2 ORDS
curl -sf https://your-internal-host/  # -k 없이도 통과해야 함
```

### Ubuntu / Debian
```bash
sudo cp /etc/ords/tls/chain.pem /usr/local/share/ca-certificates/ords-oci-chain.crt
sudo update-ca-certificates
```

## 5.4 Java truststore 등록 (ORDS / JVM 이 신뢰)

```bash
sudo $JAVA_HOME/bin/keytool -import -trustcacerts -noprompt \
  -alias ords-oci-chain \
  -file /etc/ords/tls/chain.pem \
  -keystore $JAVA_HOME/lib/security/cacerts \
  -storepass changeit
```
삭제(갱신용):
```bash
sudo $JAVA_HOME/bin/keytool -delete -alias ords-oci-chain \
  -keystore $JAVA_HOME/lib/security/cacerts -storepass changeit
```

## 5.5 이 cookbook 에서 이 cert 의 용도

이 cookbook 은 **TLS 를 LB 에서 종단**합니다 (`docs/04-ha.md` 참고).
따라서 OCI 에서 내려받은 cert/key 는 ORDS 가 직접 사용하지 않습니다.
이 chapter 의 fetch 절차가 필요한 경우는:

- **OS truststore 등록** (§5.3) — 노드의 `curl`/`openssl` 이 사내 CA 발급
  cert 를 신뢰하도록 (예: 내부 API 호출용)
- **Java truststore 등록** (§5.4) — JVM 이 신뢰하도록 (ORDS 가 outbound 로
  내부 HTTPS 호출할 때)

→ 즉 이 cert 들은 **클라이언트 신뢰용**이며, ORDS 가 서버로 종단하는 용도는 아닙니다.
LB 가 cert 를 직접 참조하므로 ORDS 노드 OS 에는 PEM 이 없어도 됩니다.

## 5.6 자동 갱신 (rotation)

OCI Certificate Service 에서 cert version 이 올라가면(예: 자동 갱신, 수동 rotate):

```bash
# 같은 스크립트만 다시 돌리면 최신 version 의 PEM 으로 덮어씀
./run.sh fetch-cert
sudo systemctl restart ords   # ORDS 직접 종단인 경우
```

cron 으로 매일 새벽 1회:
```bash
0 3 * * * cd /opt/ords-install-guide && ./run.sh fetch-cert >> logs/cert-refresh.log 2>&1 \
  && systemctl restart ords
```
(restart 가 부담이면 LB 종단으로 전환 후 LB 가 OCI cert 직접 참조하게 두는 게 깔끔)

## 5.7 트러블슈팅

| 증상 | 원인 |
|---|---|
| `private-key-pem` 이 null | OCI 내부 발급 cert — 키 export 불가. IMPORTED 로 전환 또는 LB 종단 사용 |
| `oci ... NotAuthorizedOrNotFound` | IAM 정책에 `certificate-bundles` 권한 없음 |
| `curl: SSL certificate problem` | chain 미등록 또는 update-ca-trust 미실행 |
| Java 가 여전히 안 믿음 | 다른 JDK 의 cacerts 갱신함 — `$JAVA_HOME` 이 alias(`/opt/java/current`)인지 확인 |
