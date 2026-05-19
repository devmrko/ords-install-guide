# 07. Vector + ORDS REST 데모

기존에 설치된 ORDS + ADB 환경 위에 **벡터 임베딩 + 유사도 검색 REST API** 를
한 번에 발행하는 데모입니다. 임베딩은 **OCI Generative AI** 의 Cohere
`embed-v4.0` 모델을 ADB 안에서 `DBMS_VECTOR.UTL_TO_EMBEDDING` (provider =
`ocigenai`) 로 직접 호출합니다.

단일 명령으로 다음 작업을 수행합니다.

1. ADMIN 으로 데모 스키마(`VECTOR_DEMO`) 생성, `DBMS_VECTOR` / `DBMS_VECTOR_CHAIN`
   권한 부여, OCI GenAI inference host outbound ACL 부여, ORDS 스키마 활성화
   (base = `/ords/vector/`)
2. VECTOR_DEMO 가 `DBMS_VECTOR_CHAIN.CREATE_CREDENTIAL` 로 OCI native API key
   credential 등록
3. 데모 스키마에 `DOC_CHUNKS` 테이블 생성 (`embedding VECTOR(1536, FLOAT32)`)
4. 12건의 샘플 문장 적재 — `DBMS_VECTOR.UTL_TO_EMBEDDING(text, json(params))`
   으로 OCI GenAI Cohere v4 호출 후 결과를 그대로 적재
5. ORDS module `vector.search` + template + handler 발행
6. SQL 레벨에서 검색 결과 확인 (한국어 쿼리 포함 — v4 는 multilingual)

> **임베딩 호출 경로**
>
> 본 데모는 vector-native 패키지인 `DBMS_VECTOR.UTL_TO_EMBEDDING` 의 `ocigenai`
> provider 경로를 사용합니다. credential 은 같은 namespace 의
> `DBMS_VECTOR_CHAIN.CREATE_CREDENTIAL` 로 만들어야 lookup 됩니다
> (`DBMS_CLOUD.CREATE_CREDENTIAL` 로 만든 credential 은 보이지 않음).
>
> Always Free ATP 등 일부 환경에서는 `oci://` transport 가 Instance Principal /
> Resource Principal 만 허용해서 `ORA-20401` 로 거절될 수 있습니다. 이 경우
> Paid ADB 로 옮기거나, ONNX 경로(7.6) 로 대체.

## 7.1 사전 요구사항

- ORDS 노드에서 `./run.sh all` 이 이미 완료된 상태
- ADB 가 **Oracle Database 26ai** 기반이어야 함 (`VECTOR` 타입 등 26ai 기능 사용)
- ADB 에서 OCI GenAI inference endpoint 로 outbound HTTPS 가 가능해야 함
  (`01_admin_setup.sql` 이 `DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE` 로 ACL 부여)
- OCI native API key 한 벌
  - 콘솔: `Profile > User Settings > API Keys > Add API Key` (또는 `oci setup keys`)
  - 생성 후 `User OCID`, `Tenancy OCID`, `Fingerprint`, PEM 파일 경로를 `.env` 에 기입
  - 로컬에 이미 `~/.oci/config` 가 있으면 동일 DEFAULT 프로파일 값을 그대로 사용 가능
- OCI IAM 정책: 위 user 가 GenAI inference 호출 권한을 가진 group 에 속해야 함
  ```
  allow group genai-callers to use generative-ai-family in compartment <X>
  ```

## 7.2 `.env` 설정

```bash
VECTOR_DEMO_USER=VECTOR_DEMO
VECTOR_DEMO_PASSWORD=                       # ADB 정책: 12~30자, 대/소/숫자/특수

# GenAI region — endpoint URL/host 구성에 사용
OCI_REGION=us-chicago-1

OCI_GENAI_CRED_NAME=OCI_GENAI_CRED
OCI_GENAI_MODEL=cohere.embed-v4.0
OCI_GENAI_DIM=1536                          # cohere.embed-v4.0 default. 256/512/1024/1536 선택 가능
OCI_GENAI_URL=https://inference.generativeai.${OCI_REGION}.oci.oraclecloud.com/20231130/actions/embedText
OCI_GENAI_HOST=inference.generativeai.${OCI_REGION}.oci.oraclecloud.com

# OCI native API key — ~/.oci/config 의 DEFAULT 와 동일
OCI_USER_OCID=ocid1.user.oc1..
OCI_TENANCY_OCID=ocid1.tenancy.oc1..
OCI_COMPARTMENT_OCID=ocid1.compartment.oc1..
OCI_KEY_FINGERPRINT=aa:bb:cc:...
OCI_API_KEY_PEM=/home/opc/.oci/oci_api_key.pem
```

다른 region 의 GenAI 를 사용하려면 `OCI_REGION` 만 바꾸면 `OCI_GENAI_URL` /
`OCI_GENAI_HOST` 가 함께 갱신됩니다. 차원을 줄이려면 `OCI_GENAI_DIM` (예: 1024)
을 바꾼 뒤 `./run.sh vector-demo cleanup && ./run.sh vector-demo` 로 재생성.

## 7.3 실행

```bash
./run.sh vector-demo            # 풀 셋업 (01_admin → 06_test 전체)
```

비밀번호가 `.env` 에 비어 있으면 `run.sh` 가 ADB `ADMIN_PASSWORD` 와
`VECTOR_DEMO_PASSWORD` 를 프롬프트합니다.

세분화 옵션:

| 명령 | 동작 |
|---|---|
| `./run.sh vector-demo admin`      | 사용자 + 권한 + GenAI host ACL + ORDS schema enable 만 |
| `./run.sh vector-demo credential` | 02_credential.sql 만 (PEM 갱신/key rotation 시) |
| `./run.sh vector-demo schema`     | 테이블/seed/ORDS 발행/SQL 검증 |
| `./run.sh vector-demo publish`    | ORDS 모듈만 재발행 (handler PL/SQL 수정 후) |
| `./run.sh vector-demo test`       | SQL 레벨 검증만 |
| `./run.sh vector-demo onnx`       | (선택) `optional_load_onnx.sql` 로 ONNX 모델 로드 |
| `./run.sh vector-demo cleanup`    | 99_cleanup.sql — 사용자/모델 전부 제거 |

## 7.4 REST 엔드포인트

발행되는 module 의 base path 는 `/ords/vector/docs/` 입니다.

### POST `/ords/vector/docs/search`

요청 body 스키마:

| 필드 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `q` | string | (필수) | 검색 쿼리 텍스트 |
| `k` | number | 5 | top-k 결과 수 |

요청 예:

```bash
curl -sS -X POST http://<node>:8080/ords/vector/docs/search \
     -H 'Content-Type: application/json' \
     -d '{"q": "database REST API for web apps", "k": 5}'

# 한국어 쿼리 (cohere.embed-v4.0 은 multilingual)
curl -sS -X POST http://<node>:8080/ords/vector/docs/search \
     -H 'Content-Type: application/json' \
     -d '{"q": "지하철 노선", "k": 3}'
```

응답 예시:

```json
{
  "query": "database REST API for web apps",
  "k": 5,
  "results": [
    { "id": 2, "title": "ORDS overview",        "content": "...", "distance": 0.1283 },
    { "id": 1, "title": "Oracle ADB intro",     "content": "...", "distance": 0.2691 },
    { "id": 3, "title": "Vector search 26ai",   "content": "...", "distance": 0.3402 },
    { "id": 5, "title": "PostgreSQL pgvector",  "content": "...", "distance": 0.4115 },
    { "id": 6, "title": "Load balancer basics", "content": "...", "distance": 0.5530 }
  ]
}
```

- `distance` 는 cosine 거리 (0 에 가까울수록 유사)
- `k` 생략 시 기본 5
- `q` 누락 시 HTTP 400 + `{"error":"missing field q"}`
- 핸들러는 `DBMS_VECTOR.UTL_TO_EMBEDDING` 으로 OCI GenAI 를 호출해 곧바로
  `VECTOR` 값을 받음 (별도 `TO_VECTOR` 변환 불필요)

### GET `/ords/vector/docs/`

모듈 사용법 안내 (JSON). 임베딩 모델명과 endpoint 목록 반환.

### GET `/ords/vector/docs/list`

현재 적재된 문서 목록 (id, title, dim, created_at). ORDS
`collection_feed` source_type 이므로 `?limit=&offset=` 페이지네이션 가능.

### LB 경유 호출

`docs/04-ha.md` 절차로 OCI LB + TLS 가 구성된 상태라면:

```bash
curl -sS -X POST https://ords.example.com/ords/vector/docs/search \
     -H 'Content-Type: application/json' \
     -d '{"q": "particles quantum physics", "k": 3}'
```

## 7.5 SQL 레벨 직접 검증

ORDS 없이 SQL 만으로도 검색 결과를 확인할 수 있습니다 (`06_test.sql`):

```sql
select id, title, distance
  from (
    select id, title,
           vector_distance(
             embedding,
             q_emb('pasta dish with eggs and cheese'),
             cosine
           ) as distance
      from doc_chunks
     where embedding is not null
     order by distance
     fetch first 3 rows only
  );
```

`q_emb` 는 `06_test.sql` 이 세션 내에 생성하는 헬퍼 함수로, 내부적으로
`DBMS_VECTOR.UTL_TO_EMBEDDING(text, json(params))` 을 호출해 곧바로 `VECTOR` 를
반환합니다.

## 7.6 (선택) ONNX in-DB 임베딩

GenAI REST 호출 없이 ADB 안에서 임베딩을 끝내고 싶으면 ONNX 모델을 로드해
`VECTOR_EMBEDDING(model USING text AS data)` 를 사용할 수 있습니다. 이 데모는
ONNX 경로를 **선택 사항** 으로 남겨둡니다 (`sql/vector/optional_load_onnx.sql`).

절차:

1. HuggingFace 등에서 sentence-transformer 모델 다운로드
2. Oracle 제공 변환 스크립트로 augmented ONNX zip 생성
   (`OML4Py` 의 `EmbeddingModel` 클래스 — Oracle Database 26 문서:
   <https://docs.oracle.com/en/database/oracle/oracle-database/26/vecse/import-pretrained-models-onnx-format-vector-generation-database.html>)
3. OCI Object Storage 에 업로드 → PAR 생성
4. `.env` 의 `VECTOR_MODEL_URI` / `VECTOR_MODEL_FILE` 채움
5. `./run.sh vector-demo onnx` 실행
6. `DOC_CHUNKS` 에 ONNX 임베딩용 컬럼 추가 후 `VECTOR_EMBEDDING` 으로 적재

> Oracle 공식 OML-Resources 버킷의 공개 PAR 은 회전/만료되는 경우가 있어
> 기본 플로우에서 제외했습니다. 자체 변환 + 자체 버킷 PAR 사용을 권장합니다.

## 7.7 보안 / 운영 고려사항

- 현재 모듈은 **익명 호출 허용** (`p_auto_rest_auth => false`). 운영 사용 시
  `ords.define_privilege` + role 매핑으로 OAuth2 토큰 또는 Basic 인증 강제
- GenAI 호출은 외부 API 이므로 토큰/요청 수에 대한 과금이 발생. handler 에 rate
  limit / quota 도입 권장 (예: APEX 의 throttle, ORDS `pre-hook` 등)
- `VECTOR_DISTANCE(..., cosine)` 는 정확검색이므로 데이터 규모 증가 시
  `04_seed.sql` 이 생성하는 NEIGHBOR PARTITIONS 인덱스 + `fetch approx first k`
  사용으로 전환 (handler 의 `order by ... fetch first` 절 수정)
- credential 은 `DBMS_VECTOR_CHAIN.CREATE_CREDENTIAL` 로 VECTOR_DEMO 스키마에
  생성되며 PEM private key 가 DB 안에 저장됨. 절대 export 되지 않도록 운영 시
  `USER_CREDENTIALS` 뷰 접근 권한 관리 필요. 키 회전은
  `./run.sh vector-demo credential` 로 재생성 (drop + create)
- 임베딩 호출 권한은 IAM 의 user/group 정책에 의존
  (예: `allow group genai-callers to use generative-ai-family in compartment X`)
- `DBMS_VECTOR` 의 `ocigenai` 경로는 ADB 의 user-level network ACL 이 GenAI
  inference host 로 outbound 를 허용해야 함 (`01_admin_setup.sql` 처리)

## 7.8 정리

```bash
./run.sh vector-demo cleanup
```

- `VECTOR_DEMO` 사용자 cascade drop → 테이블/인덱스/credential/ORDS 메타 함께 제거
- ONNX 모델 `DOC_MODEL` 이 존재하면 함께 drop (없으면 skip)
- GenAI 호스트 ACE 는 다른 사용자에게 영향 줄 수 있어 그대로 둠
  (필요 시 `DBMS_NETWORK_ACL_ADMIN.REMOVE_HOST_ACE` 로 별도 제거)
