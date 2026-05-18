# ORDS Install Guide (Linux + ADB + HA)

ORDS(Oracle REST Data Services)를 **Linux 위에 wget 기반으로 설치**하고,
**OCI Load Balancer + 사설 TLS 인증서**까지 묶어 HA 구성하는 cookbook.

> 그냥 clone → `.env` 채우기 → `./run.sh all` 한 줄이면 끝나도록 만든 게 목표.

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
./run.sh ha-tf apply                    # OCI LB + 사설 인증서 등록까지 terraform
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
| TLS | LB 종단 — OCI Certificate Service에 사설 cert import |

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
    ├── main.tf             # LB + backend set + listener + 사설 cert import
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
