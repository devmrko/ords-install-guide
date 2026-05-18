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

- `true` → PEM 들을 `oci_certificates_management_certificate` 로 새로 import
  (셸에서 `TF_VAR_cert_pem` / `TF_VAR_key_pem` / `TF_VAR_chain_pem` 으로 주입)
- `false` → 이미 OCI Cert Service 에 등록된 `cert_ocid` 사용

새로 import 하는 경우 인증서/키는 절대 tfvars 평문에 두지 말고 `.env` → 환경변수 경로로만.

## destroy 주의

`terraform destroy` 는 LB / backend set / listener / **import 한 인증서까지** 같이 지웁니다.
인증서가 다른 서비스에서 참조 중이면 분리 관리 필요 (state 에서 `terraform state rm` 후 콘솔에서 별도 관리).
