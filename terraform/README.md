# terraform/

ORDS HA용 OCI Load Balancer + 사설 TLS 인증서 IaC.

## 사전조건

- `oci` CLI 설치 + `oci setup config` 완료 (`~/.oci/config`)
- Terraform 1.3+
- 위 두 가지로 provider 가 자동 인증됨 (별도 키 설정 불필요)

## 두 가지 실행 방식

### A. `run.sh` 통해 (권장)
```bash
# 레포 루트에서
./run.sh ha-tf plan
./run.sh ha-tf apply
./run.sh ha-tf output
./run.sh ha-tf destroy
```
→ `.env` 의 값을 TF_VAR_* 로 자동 주입.

### B. terraform 단독
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars
terraform init
terraform plan
terraform apply
```

## 사설 인증서 처리 (`import_cert`)

- `true` → PEM 들을 `oci_certificates_management_certificate` 로 새로 import.
  `06_lb_terraform.sh` 가 `.env` 의 PEM 파일들을 **임시 `.secrets.auto.tfvars`(권한 600)** 로 만들어
  Terraform 에 전달하고 종료 시 `shred -u` 로 삭제. (환경변수 노출 회피)
- `false` → 이미 OCI Cert Service 에 등록된 `cert_ocid` 사용

## State 보안 (⚠️ 중요)

Terraform state 파일에는 cert_pem / key_pem 이 **평문 저장**됨. local backend(기본)는 디스크에 그대로 남으므로 운영에서는 반드시:

1. `backend.tf.example` 복사 → OCI Object Storage(KMS 암호화) 같은 원격 backend 사용
2. 버킷에 IAM 으로 운영 관리자만 read/write 허용
3. 버킷 versioning 활성화
4. 가능하면 인증서 스택을 별도 state 로 분리

```bash
cp backend.tf.example backend.tf
vi backend.tf       # bucket, region 등 채움
terraform init -migrate-state
```

## destroy 주의

`terraform destroy` 는 LB / backend set / listener 만 지웁니다.
인증서 리소스에는 `lifecycle { prevent_destroy = true }` 가 걸려있어 destroy 실패. 정말 지우려면:
- `main.tf` 의 해당 `lifecycle` 블록 제거 → `apply` → `destroy`
- 또는 `terraform state rm oci_certificates_management_certificate.private[0]` 후 콘솔에서 별도 관리
