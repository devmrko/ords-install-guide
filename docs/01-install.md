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

# Eclipse Temurin 21 LTS 최신 GA (Adoptium API 가 latest 리디렉트)
wget -nv -O /tmp/jdk.tar.gz \
  "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse"
sudo tar -xzf /tmp/jdk.tar.gz -C /opt/java

# alias 갈아끼우기
NEW_JDK=$(ls -1dt /opt/java/jdk-* | head -1)
sudo ln -sfn "$NEW_JDK" /opt/java/current
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
