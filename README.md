# ORDS Install Guide (Linux + ADB + HA)

ORDS(Oracle REST Data Services)를 **Linux 위에 wget 기반으로 설치**하고,
**OCI Load Balancer + 사설 TLS 인증서**까지 묶어 HA 구성하는 cookbook.

> 그냥 clone → `.env` 채우기 → `./run.sh all` 한 줄이면 끝나도록 만든 게 목표.

---

## Prerequisites

### ORDS 노드 (Linux VM)
- Oracle Linux 8/9, RHEL 8/9, Ubuntu 22.04+ (bash 4+; firewalld 또는 ufw 자동 감지)
- 외부 인터넷 egress (JDK/ORDS/sqlcl zip 다운로드)
- ADB private endpoint 또는 public endpoint 로 1522/TCP egress
- 충분 디스크: JDK(~400MB) + ORDS(~600MB) + sqlcl(~500MB) + 로그 여유 → 최소 8GB
- 메모리: 4GB 권장 (JVM heap 기본 + Jetty)
- sudo 권한 있는 계정 (스크립트가 `sudo` 호출)

### 컨트롤 머신 (스크립트 돌리는 곳 — ORDS 노드 자체일 수도 있음)
- `bash` (macOS 도 OK — 3.2 호환됨)
- `oci` CLI (≥ 3.40, `~/.oci/config` 준비)
- `terraform` (≥ 1.3) — ha-tf 트랙 쓸 때만
- `jq` (≥ 1.6), `openssl` (≥ 1.1.1)
- LB-only 트랙은 ORDS 노드 위에서 안 돌려도 됨 (별도 머신에서 OCI CLI 만 있으면 됨)

### ADB
- Wallet zip 또는 풀린 디렉토리 (cwallet.sso 포함). 1년 넘은 wallet 은 PKIX fail 가능 → 콘솔에서 새로 download 권장
- ADMIN 비밀번호
- ADB 가 ORDS 노드 subnet 에서 도달 가능해야 함 (Network ACL / private endpoint 확인)

---

## 필요한 OCI IAM 정책

스크립트를 돌리는 user/group 이 다음 권한을 가져야 합니다 (단순화 — 운영은 더 좁힐 것):

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

> `OCI_REGION` 이 `~/.oci/config` 의 DEFAULT 와 다르면 `.env` 에 명시. 안 그러면
> terraform 이 엉뚱한 region 으로 호출해서 NotAuthorizedOrNotFound 로 죽음.

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
├── README.md
├── run.sh                  # 단일 진입점 (디스패처)
├── .env.example
├── .gitignore
├── docs/
│   ├── 01-install.md       # 사전준비 + JDK alias + ORDS 다운로드/배치
│   ├── 02-configure.md     # ords install (pool, wallet 연결)
│   ├── 03-run.md           # systemd, 로그, smoke test
│   ├── 04-ha.md            # 2노드+ LB, 웹콘솔/Terraform, 사설 cert 등록
│   ├── 05-cert-from-oci.md # OCI Cert Service → OS 로 가져와 신뢰 등록
│   └── 06-operations.md    # 백업/복구, 모니터링, logrotate, cert 자동갱신
├── scripts/
│   ├── 00_prereq.sh
│   ├── 01_install.sh
│   ├── 02_configure.sh
│   ├── 03_start.sh
│   ├── 04_smoke.sh
│   ├── 05_ha.sh
│   ├── 06_lb_terraform.sh
│   ├── 07_fetch_oci_cert.sh
│   ├── 99_teardown.sh
│   └── lib/common.sh
├── sql/
│   └── smoke_test.sql
├── config/
│   └── ords.service.tmpl   # systemd unit (envsubst로 치환)
└── terraform/
    ├── README.md
    ├── main.tf             # LB + backend set + listener + 사설 cert (LB-attached PEM)
    ├── network.tf          # (선택) VCN + IG + RT + SL + Subnet — create_network=true 시
    ├── variables.tf
    ├── outputs.tf
    └── terraform.tfvars.example
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
