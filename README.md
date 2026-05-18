# ORDS Install Guide (Linux + ADB + HA)

ORDS (Oracle REST Data Services) 를 Linux 환경에 wget 기반으로 설치하고,
OCI Load Balancer 및 사설 TLS 인증서까지 포함하여 HA 구성을 완성하는 cookbook 입니다.

> 저장소를 clone 한 뒤 `.env` 를 채우고 `./run.sh all` 한 번으로 설치가 완료되도록
> 설계되어 있습니다.

---

## 개요

> Oracle/OCI 스택을 처음 다루는 엔지니어를 위한 배경 설명입니다. 이미 익숙하다면
> [Prerequisites](#prerequisites) 로 건너뛰십시오.

### ORDS (Oracle REST Data Services)

Oracle Database 의 테이블과 PL/SQL 객체를 HTTP REST API 로 노출시키는 Java 웹
애플리케이션입니다. 클라이언트는 SQL 드라이버 없이 HTTP 호출만으로 데이터에
접근할 수 있습니다. 내부적으로는 임베디드 Jetty 컨테이너 위에서 동작하며, JDBC
커넥션 풀을 통해 데이터베이스에 연결합니다.

### ADB (Autonomous Database) 와 wallet

ADB 는 Oracle 의 매니지드 데이터베이스 서비스입니다. 기본적으로 TLS 상호 인증
(mutual TLS) 을 요구하므로, 클라이언트는 별도로 발급된 클라이언트 인증서·CA
체인·`tnsnames.ora` 를 제시해야 합니다. 이 파일들을 묶은 압축 패키지가 **wallet**
이며 (`cwallet.sso`, `ewallet.p12`, `tnsnames.ora` 등 포함), ORDS 는 이 wallet 을
사용해 ADB 에 접속합니다. 따라서 작업의 첫 단계는 OCI 콘솔에서 wallet 을
다운로드하여 ORDS 노드에 배치하는 것입니다.

### Load Balancer 도입 이유

- **가용성**: 단일 ORDS 노드 장애에 대비해 2노드 active-active 구성을 채택하고,
  Load Balancer 가 라운드로빈으로 트래픽을 분산합니다.
- **세션 무상태성**: ORDS 는 stateless 이므로 sticky session 이 불필요하며,
  노드 간 세션 동기화 부담이 없습니다.
- **TLS 종단 일원화**: Load Balancer 에서 TLS 를 종단하면 백엔드 노드는 평문
  HTTP 만 처리하면 되므로, 인증서 갱신 시 ORDS 재시작이나 노드별 동기화 작업이
  필요하지 않습니다.

### 본 cookbook 의 자동화 범위

**자동화 대상**

- Oracle JDK 21 설치
- ORDS 및 SQLcl 다운로드·배치·symlink 구성
- `ords install adb --silent` 를 통한 풀 생성 및 wallet 연결
- systemd 서비스 등록 및 기동
- DB 연결 검증(SELECT 1) 및 `/ords/_/landing` 스모크 테스트
- OCI Load Balancer 및 사설 인증서 등록 (Terraform)
- VCN 및 Subnet 자동 생성 (선택)
- firewalld 또는 ufw 의 ORDS 포트 자동 개방

**자동화 범위 외 (수동 수행 필요)**

- OCI Compartment 및 IAM 사용자/정책 생성 — 콘솔에서 별도 수행
- Linux VM 프로비저닝 — `oci compute instance launch` 등으로 별도 수행
- DNS A 레코드 등록 — 외부 DNS 서비스에서 수행 (`docs/04-ha.md` §4.6 참고)
- APEX 설치 — 별도 문서로 분리

### 전체 구성 흐름

```
[1] OCI 콘솔                       [2] 컨트롤 머신                   [3] ORDS 노드 (Linux VM)
─────────────────                  ─────────────────                  ───────────────────────
ADB 생성 및 wallet 다운로드          oci setup config (~/.oci/config)   git clone <this repo>
Compartment / IAM 정책 설정          terraform / oci / jq 설치          cp .env.example .env
VCN / Subnet (선택)                                                     wallet 배치
VM 프로비저닝 (compute)                                                 sudo ./run.sh all
                                                                       └ prereq → install →
                                                                         configure → start → smoke

                                   [4] Load Balancer 구성 (택1)
                                   ────────────────────────────
                                   콘솔 수동 (docs/04-ha.md §4.4)
                                   또는 Terraform (§4.5):
                                     cd ords-install-guide
                                     ./run.sh ha-tf apply
                                       └ VCN / Subnet (선택)
                                       └ LB + backend set
                                       └ HTTPS listener + 인증서 PEM 첨부
                                       └ HTTP → HTTPS 301 리다이렉트

                                   [5] DNS 레코드 등록
                                   ────────────────────────────
                                   A record  ords.example.com → LB IP
                                   (PoC 환경에서는 /etc/hosts 로 대체 — §4.6)
```

---

## 구성 시나리오별 권장 절차

| 시나리오 | 권장 절차 |
|---|---|
| 단일 노드에서 ORDS 만 기동하여 REST 호출 검증 | `./run.sh all` 실행. Load Balancer 및 인증서 단계 생략 |
| 2노드 + Load Balancer 풀구성, 신규 Compartment 에서 시작 | `.env`: `OCI_CREATE_NETWORK=true` 설정 → VM 프로비저닝 후 각 노드에서 `./run.sh all` → 컨트롤 머신에서 `./run.sh ha-tf apply` |
| 기존 VCN/Subnet 활용, Load Balancer 와 인증서만 추가 | `.env`: `OCI_CREATE_NETWORK=false` + `OCI_LB_SUBNET_OCID=...` 설정 → `./run.sh ha-tf apply` |
| OCI Certificate Service 에 기등록된 인증서 재사용 | `.env`: `OCI_CERT_OCID=ocid1...` 설정, PEM 경로 변수는 공란 → `./run.sh ha-tf apply` |
| 내부망 전용 구성 (인터넷 미노출) | `.env`: `LB_IS_PRIVATE=true` 설정 |
| 사내 CA 발급 인증서를 OS truststore 에만 등록 (LB 미사용) | `./run.sh fetch-cert` 실행 (`docs/05-cert-from-oci.md` 참고) |

---

## Prerequisites

### ORDS 노드 (Linux VM)
- Oracle Linux 8/9, RHEL 8/9, Ubuntu 22.04+ (bash 4+; firewalld 또는 ufw 자동 감지)
- 외부 인터넷 egress (JDK/ORDS/sqlcl zip 다운로드)
- ADB private endpoint 또는 public endpoint 로 1522/TCP egress
- 충분 디스크: JDK(~400MB) + ORDS(~600MB) + sqlcl(~500MB) + 로그 여유 → 최소 8GB
- 메모리: 4GB 권장 (JVM heap 기본 + Jetty)
- sudo 권한 있는 계정 (스크립트가 `sudo` 호출)

### 컨트롤 머신 (스크립트 실행 환경 — ORDS 노드와 동일해도 무방)
- `bash` (macOS 의 3.2 도 호환)
- `oci` CLI (≥ 3.40, `~/.oci/config` 사전 설정)
- `terraform` (≥ 1.3) — ha-tf 트랙 사용 시
- `jq` (≥ 1.6), `openssl` (≥ 1.1.1)
- LB-only 트랙은 ORDS 노드와 별개 머신에서 OCI CLI 만으로 실행 가능

### ADB
- Wallet zip 또는 풀린 디렉토리 (cwallet.sso 포함). 1년 넘은 wallet 은 PKIX fail 가능 → 콘솔에서 새로 download 권장
- ADMIN 비밀번호
- ADB 가 ORDS 노드 subnet 에서 도달 가능해야 함 (Network ACL / private endpoint 확인)

---

## 필요한 OCI IAM 정책

스크립트를 실행하는 user/group 에 다음 권한이 필요합니다 (예시는 단순화된 형태이며, 운영 환경에서는 범위를 더 좁혀 부여하십시오):

```
# LB 트랙 (./run.sh ha-tf)
allow group <ords-admins> to manage load-balancers in compartment <comp>
allow group <ords-admins> to use virtual-network-family in compartment <comp>
allow group <ords-admins> to manage certificate-bundles in compartment <comp>
allow group <ords-admins> to read certificates in compartment <comp>

# 신규 VCN 까지 terraform 으로 생성 시 (OCI_CREATE_NETWORK=true)
allow group <ords-admins> to manage vcns in compartment <comp>
allow group <ords-admins> to manage subnets in compartment <comp>
allow group <ords-admins> to manage internet-gateways in compartment <comp>
allow group <ords-admins> to manage route-tables in compartment <comp>
allow group <ords-admins> to manage security-lists in compartment <comp>

# OCI Cert Service 에서 사설 cert 를 OS 로 fetch 할 때 (./run.sh fetch-cert)
allow group <ords-admins> to read certificate-bundles in compartment <comp>
```

> `OCI_REGION` 값이 `~/.oci/config` 의 DEFAULT 프로파일 region 과 다를 경우
> 반드시 `.env` 에 명시하십시오. 누락 시 Terraform 이 잘못된 region 으로 API 를
> 호출하여 `NotAuthorizedOrNotFound` 오류로 실패합니다.

---

## Quickstart

```bash
git clone https://github.com/devmrko/ords-install-guide.git
cd ords-install-guide
cp .env.example .env && vi .env        # 값 채우기 (특히 ADB_TNS, WALLET_PATH)
./run.sh all                            # prereq → install → configure → start → smoke
```

HA 2번째 노드에서:
```bash
# .env 에서 HA_NODE_ROLE=secondary 로만 바꾸고
./run.sh all
```

LB:
```bash
# 옵션 A: 기존 VCN/Subnet 이 있으면
#   .env 의 OCI_LB_SUBNET_OCID 채우고 OCI_CREATE_NETWORK=false
# 옵션 B: 빈 컴파트먼트에서 VCN 까지 한 번에
#   .env 의 OCI_CREATE_NETWORK=true (VCN_CIDR, PUBLIC_SUBNET_CIDR 기본값 OK)
./run.sh ha-tf apply                    # LB + (옵션 B면 VCN까지) + 사설 인증서 등록
# 또는 웹 콘솔로 직접: docs/04-ha.md §4.4
```

---

## 전제 매트릭스 (기본값)

| 항목 | 값 |
|---|---|
| OS | Oracle Linux 8/9, RHEL 8/9, Ubuntu 22.04+ |
| 백엔드 DB | Autonomous Database (ADB) — wallet 사용 |
| 설치 방식 | wget + unzip (RPM 미사용) |
| Java | Oracle JDK 21 LTS (`/opt/java/current` symlink) — OCI 워크로드 OTN 무료 |
| 실행 모드 | standalone (내장 Jetty) + systemd |
| LB | OCI Load Balancer (Flexible shape) |
| TLS | LB 종단 — `oci_load_balancer_certificate` 로 PEM 직접 attach (또는 기존 Cert Service OCID 참조) |

다른 조합은 `.env`만 바꿔서 대응 (RAC / on-prem DB / 다른 LB 등).

---

## 디렉토리

```
ords-install-guide/
├── README.md                       # 본 문서 — Prereq + IAM 정책 + Quickstart + 구조
├── run.sh                          # 단일 진입점 디스패처. 모든 작업은 ./run.sh <subcmd> 로 통일
├── .env.example                    # 환경변수 템플릿. cp .env.example .env 후 값 채움 (gitignored)
├── .gitignore                      # .env, wallet, *.pem, terraform state 등 비밀 차단
│
├── docs/                           # 절차/배경/트러블슈팅 문서. 스크립트와 1:1 매핑은 아님
│   ├── 01-install.md               # JDK/ORDS/sqlcl 다운로드 + alias symlink 패턴 설명
│   ├── 02-configure.md             # ords install adb 흐름: pool 생성 + wallet 연결 + 계정 3종
│   ├── 03-run.md                   # systemd unit 동작 + 로그 위치 + smoke test 해석
│   ├── 04-ha.md                    # 2노드 + OCI LB + 사설 TLS — 웹콘솔/Terraform 양트랙 + DNS/hosts 설명
│   ├── 05-cert-from-oci.md         # OCI Cert Service의 cert를 OS truststore/JVM truststore에 등록
│   ├── 06-operations.md            # 배포 후: 백업/복구, 모니터링, logrotate, cert 자동갱신 cron
│   └── 07-vector-rest.md           # ADB 23ai VECTOR + ONNX 임베딩 + ORDS 검색 모듈 데모
│
├── scripts/                        # 모두 idempotent. 재실행 시 기존 상태 감지하면 skip
│   ├── 00_prereq.sh                # 패키지 확인(wget/unzip/...) + oracle 유저 생성 + JDK21 + firewalld/ufw 8080 개방
│   ├── 01_install.sh               # ORDS zip + sqlcl zip 다운 → /opt/oracle/ords/ords-X.Y.Z + symlink (24.x flat / older nested 자동 감지)
│   ├── 02_configure.sh             # wallet.zip 자동 생성 + ords install adb --silent (admin/db_user/gateway_user 3계정) + jdbc pool 사이즈 set
│   ├── 03_start.sh                 # config/ords.service.tmpl 을 envsubst로 치환 → /etc/systemd/system/ + enable + start
│   ├── 04_smoke.sh                 # sqlcl로 ADB SELECT 1 + curl /ords/_/landing 응답코드 확인 (200/302 OK)
│   ├── 05_ha.sh                    # secondary 노드 부트스트랩 안내 + 양 노드 health 확인 (LB는 별도 ha-tf 또는 콘솔)
│   ├── 06_lb_terraform.sh          # terraform 래퍼. PEM은 환경변수 대신 .secrets.auto.tfvars(600) 로 주입 (ps/proc 노출 방지)
│   ├── 07_fetch_oci_cert.sh        # OCI CLI로 cert-bundle get → /etc/ords/tls/*.pem 으로 저장 (rotation 시 재실행)
│   ├── 08_vector_demo.sh           # ADB 위에 VECTOR_DEMO 스키마 + ONNX 모델 + ORDS vector.search 모듈 발행
│   ├── 99_teardown.sh              # 역순 정리. systemd disable → 디렉토리 삭제. 확인 프롬프트 있음
│   └── lib/common.sh               # 공용 함수: log/ok/warn/die, as_root, require_env, need_cmd, fetch(wget+retry), init_logging
│
├── sql/
│   ├── smoke_test.sql              # 04_smoke.sh가 sqlcl로 던질 SQL — SELECT 1 from dual, ORDS 메타 확인 등
│   └── vector/                     # 07-vector-rest.md 데모용 SQL 묶음
│       ├── 01_admin_setup.sql      # ADMIN: VECTOR_DEMO 사용자 생성 + ORDS schema enable (base=/ords/vector/)
│       ├── 02_load_onnx.sql        # ADMIN: DBMS_CLOUD.GET_OBJECT → DBMS_VECTOR.LOAD_ONNX_MODEL 로 임베딩 모델 등록
│       ├── 03_schema.sql           # VECTOR_DEMO: DOC_CHUNKS(VECTOR(384,FLOAT32)) + IVF 인덱스
│       ├── 04_seed.sql             # 12건 샘플 INSERT + VECTOR_EMBEDDING() 자동 채움
│       ├── 05_ords_publish.sql     # module vector.search + POST/GET handler 정의
│       ├── 06_test.sql             # SQL 레벨에서 top-k 유사 검색 결과 확인
│       └── 99_cleanup.sql          # 사용자/모델 cascade drop
│
├── config/
│   └── ords.service.tmpl           # systemd unit 템플릿. ${ORDS_HOME}, ${ORDS_CONFIG}, ${JAVA_HOME}, ${ORDS_USER}, ${ORDS_PORT} 치환
│
└── terraform/                      # ha-tf 트랙 전용 (LB + 선택적 VCN). state는 기본 local backend
    ├── README.md                   # terraform 디렉토리 사용법 + state 보안 + remote backend 마이그레이션
    ├── main.tf                     # LB(Flexible) + backend_set + HTTP(80→443 redirect)/HTTPS(443) listener + oci_load_balancer_certificate(LB-attached PEM)
    ├── network.tf                  # (선택) OCI_CREATE_NETWORK=true 면 VCN+IG+RT+SL+Subnet 자동 생성. 아니면 var.subnet_ocid 그대로 사용
    ├── variables.tf                # 모든 입력 변수 정의 (region, compartment, network mode, LB shape/BW, cert PEM, healthcheck 등)
    ├── outputs.tf                  # lb_public_ip, lb_ocid, cert_ref, vcn_ocid, subnet_ocid — 후속 작업이 참조
    ├── terraform.tfvars.example    # tfvars 직접 채우고 싶을 때 (보통은 .env → TF_VAR_* 자동 주입 쓰면 됨)
    └── backend.tf.example          # 운영 전환 시 OCI Object Storage로 state 옮길 때 참고할 backend 설정
```

---

## run.sh 서브커맨드

```
./run.sh prereq      # OS 패키지 확인 + JDK 받아서 alias symlink
./run.sh install     # ORDS zip 받아서 ORDS_HOME alias로 배치
./run.sh configure   # ords install --silent 로 pool 생성, wallet 연결
./run.sh start       # systemd unit 배포 + enable + start
./run.sh smoke       # SQL 검증 + curl /ords/_/landing
./run.sh ha          # HA secondary 노드 부트스트랩 안내 + 검증
./run.sh ha-tf       {plan|apply|destroy|output}   # OCI LB + cert (Terraform)
./run.sh fetch-cert  # OCI Cert Service 의 cert 를 OS 로 내려받아 truststore 등록
./run.sh vector-demo {all|admin|onnx|schema|publish|test|cleanup}
                     # ADB 23ai + ORDS 위에 ONNX 임베딩 + vector 검색 REST 모듈 발행
./run.sh all         # prereq~smoke 순차
./run.sh teardown    # 역순 정리
```

대부분 스텝은 **idempotent** — 재실행 시 기존 상태 감지하면 skip.
예외:
- `teardown` 은 의도적으로 1회성 (확인 프롬프트 있음)
- `configure` 의 `ords install adb` 는 풀이 이미 있으면 skip 하지만, 부분 실패 후 재시도는 `99_teardown.sh` 로 config 비운 뒤 재시도가 안전

---

## 보안 노트

- `.env`에 비밀번호 평문 두는 건 **개발/PoC 한정**. 운영은:
  - `read -s` 프롬프트 (run.sh가 비어있으면 자동으로 물어봄)
  - `oci vault` / `pass` / `op` 같은 시크릿 매니저에서 주입
- TLS 개인키(`*.pem`, `*.key`)는 `.gitignore`로 차단되어 있음. **절대 커밋 금지.**
- ADB wallet(`wallet/`, `*.sso`, `*.p12`)도 동일.

---

## 트러블슈팅

각 스텝 스크립트 실패 시 `logs/run-*.log` 참고.
도구별 최소 버전: `oci ≥ 3.40`, `terraform ≥ 1.3`, `jq ≥ 1.6`, `openssl ≥ 1.1.1`.

## 운영 (deploy 후)

`docs/06-operations.md` — 백업/복구 절차, 모니터링 지표, logrotate, 인증서 자동갱신 안전 cron.
