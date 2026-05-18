# 01. 설치 (사전준비 + JDK + ORDS)

> 자동 실행: `./run.sh prereq && ./run.sh install`
> 이 문서는 그 안에서 무엇이 일어나는지, 손으로 할 땐 어떻게 하는지 설명합니다.

## 1.1 사전 패키지

```bash
# Oracle Linux / RHEL
sudo yum install -y wget unzip tar curl
# Ubuntu
sudo apt update && sudo apt install -y wget unzip tar curl
```

## 1.2 oracle 유저/그룹

```bash
sudo groupadd oinstall
sudo useradd -m -g oinstall oracle
```

## 1.3 JDK — alias(symlink) 패턴

운영 중 JDK 업그레이드를 무중단으로 하려면 **버전 박힌 디렉토리 + `current` symlink** 패턴이 깔끔.

```bash
sudo mkdir -p /opt/java

# Oracle JDK 21 LTS 최신 (OCI 워크로드는 OTN 라이선스로 무료)
wget -nv -O /tmp/jdk.tar.gz \
  "https://download.oracle.com/java/21/latest/jdk-21_linux-x64_bin.tar.gz"
sudo tar -xzf /tmp/jdk.tar.gz -C /opt/java

# alias 갈아끼우기 (tar 풀린 jdk-21.0.x 자동 감지)
NEW_JDK=$(ls -1dt /opt/java/jdk-* | head -1)
sudo ln -sfn "$NEW_JDK" /opt/java/current
```

### 왜 Oracle JDK인가 (OCI 배포 기준)

#### 라이선스 — OCI에서는 그냥 무료

- **NFTC (No-Fee Terms and Conditions)** 라이선스가 Java 17부터 적용 — **운영(상용 포함) 무료**
- 추가로 OCI 컴퓨트 인스턴스에서 Oracle JDK를 쓰면 **"Oracle Linux 가입자 혜택"** 으로
  무한 갱신/지원 묶음 (별도 구독 불필요)
- Oracle Linux 8/9 의 기본 yum 리포에 `jdk-21` 들어있어 `dnf install jdk-21` 로도 가능
  (이 가이드는 일관성 위해 wget + symlink 패턴 유지)

> 비교: 다른 클라우드/온프렘 운영에서는 NFTC 가 적용은 되지만 **지원/패치 의무**가 다름.
> OCI 밖이면 Temurin/Corretto 같은 OpenJDK 디스트로 가는 게 깔끔.

#### OCI 환경에서 Oracle JDK 이점

| 항목 | 내용 |
|---|---|
| **JMS (Java Management Service)** | OCI 콘솔에서 fleet 단위 JDK 인벤토리/취약점 스캔/사용추적 — **OCI 사용자 무료** |
| **GraalVM Enterprise** | OCI 위에서는 GraalVM **Enterprise** edition 무료. JIT/AOT 성능 향상 (ORDS 같은 long-running JVM 에 유의미한 throughput 개선) |
| **패치 주기** | 분기별 CPU(Critical Patch Update) 즉시 반영. OpenJDK 디스트로 들 보다 보통 빠름 |
| **Oracle Linux 통합** | yum 리포 + `update-crypto-policies` 같은 OL 보안 정책과 호환 가장 잘 검증됨 |
| **ORDS 와 같은 벤더** | 호환성 이슈 발생 시 Oracle 지원 한 곳에서 처리 (ORDS + JDK + ADB 모두 Oracle) |
| **장기 LTS** | Java 21 LTS = 2031년까지 패치 (NFTC 무료 패치는 다음 LTS 출시 + 1년까지) |

#### Temurin 대비 실질 차이 (OCI 안에서)

- 코어 JVM은 OpenJDK upstream으로 거의 동일
- 차이는 **번들 도구 + 운영 도구 + 지원**:
  - Oracle JDK + GraalVM EE = JIT 향상
  - Oracle JDK + JMS = 운영 관측성
  - 둘 다 OCI 사용자만 무료
- → **OCI 운영이면 Oracle JDK 가 명확한 선택**. 그 외에는 별 차이 없음.

#### 폴백 (OCI 아닐 때)

`.env` 의 `JDK_URL` 만 갈아끼우면 됨:
```bash
# Temurin
JDK_URL=https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse
# Amazon Corretto
JDK_URL=https://corretto.aws/downloads/latest/amazon-corretto-21-x64-linux-jdk.tar.gz
```

이후 모든 곳에서 **`JAVA_HOME=/opt/java/current`** 만 참조. 업그레이드 시:
```bash
# 새 버전 받아 풀고 symlink만 갈아끼움
sudo ln -sfn /opt/java/jdk-21.0.6+x /opt/java/current
sudo systemctl restart ords
# 롤백
sudo ln -sfn /opt/java/jdk-21.0.5+x /opt/java/current
```

`/etc/profile.d/ords-java.sh` 에 PATH 박아두면 새 셸 자동 적용:
```bash
export JAVA_HOME=/opt/java/current
export PATH=$JAVA_HOME/bin:$PATH
```

## 1.4 ORDS 다운로드/배치 (같은 alias 패턴)

```bash
sudo mkdir -p /opt/oracle/ords
wget -nv -O /tmp/ords.zip \
  "https://download.oracle.com/otn_software/java/ords/ords-latest.zip"

# zip 안 최상위가 ords-X.Y.Z 형태
sudo unzip -q /tmp/ords.zip -d /opt/oracle/ords
sudo ln -sfn /opt/oracle/ords/ords-24.x.x /opt/oracle/ords/current
```

`ORDS_HOME=/opt/oracle/ords/current` 로 통일.

## 1.5 sqlcl (smoke test 용)

```bash
wget -nv -O /tmp/sqlcl.zip \
  "https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip"
sudo unzip -q /tmp/sqlcl.zip -d /opt/oracle
# → /opt/oracle/sqlcl/bin/sql
```

## 1.6 검증

```bash
/opt/java/current/bin/java -version
/opt/oracle/ords/current/bin/ords --version
/opt/oracle/sqlcl/bin/sql -V
```
