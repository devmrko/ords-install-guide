# 07. Vector + ORDS REST 데모

기존에 설치된 ORDS + ADB 환경 위에 **벡터 임베딩 + 유사도 검색 REST API** 를
한 번에 발행하는 데모입니다. 기본 플로우는 **OCI Generative AI** 의 Cohere
임베딩 모델 두 종 (multilingual v3 / embed v4) 을 서버측에서 호출하여 같은
텍스트에 대해 두 컬럼을 나란히 저장하고, REST handler 에서 `by=v3|v4` 파라미터로
어느 모델을 사용할지 선택합니다.

단일 명령으로 다음 작업을 수행합니다.

1. ADMIN 으로 데모 스키마(`VECTOR_DEMO`) 생성, GenAI 엔드포인트 ACL 부여,
   ORDS 스키마 활성화 (base = `/ords/vector/`)
2. 데모 스키마에 `DOC_CHUNKS` 테이블 생성
   (`embedding_v3 VECTOR(1024, FLOAT32)`, `embedding_v4 VECTOR(*, FLOAT32)`)
3. 12건의 샘플 문장 적재 — `DBMS_VECTOR.UTL_TO_EMBEDDING` 으로 두 모델 자동 호출
4. ORDS module `vector.search` + template + handler 발행
5. SQL 레벨에서 두 컬럼 검색 결과를 비교

## 7.1 사전 요구사항

- ORDS 노드에서 `./run.sh all` 이 이미 완료된 상태
- ADB 가 **Oracle Database 23ai** 기반이어야 함 (`VECTOR` 타입 /
  `DBMS_VECTOR.UTL_TO_EMBEDDING` 등 23ai 이상 기능 사용)
- ADB 에서 OCI Generative AI 엔드포인트로 outbound HTTPS 가능
- 다음 중 하나의 GenAI 인증 자격 보유:
  - **Resource Principal** (`OCI$RESOURCE_PRINCIPAL`) — ADB 가 동일 tenancy 의
    GenAI 서비스 호출 권한을 IAM 정책으로 받은 상태
  - ADMIN 이 만든 **NATIVE OCI credential**
    (`DBMS_CLOUD.CREATE_CREDENTIAL` with `user_ocid` / `tenancy_ocid` /
    `private_key` / `fingerprint`)

## 7.2 `.env` 설정

```bash
VECTOR_DEMO_USER=VECTOR_DEMO
VECTOR_DEMO_PASSWORD=                       # ADB 정책: 12~30자, 대/소/숫자/특수

OCI_GENAI_CREDENTIAL=OCI$RESOURCE_PRINCIPAL
OCI_GENAI_ENDPOINT=https://inference.generativeai.us-chicago-1.oci.oraclecloud.com/20231130/actions/embedText
OCI_GENAI_MODEL_V3=cohere.embed-multilingual-v3.0
OCI_GENAI_MODEL_V4=cohere.embed-v4.0
```

다른 region 의 GenAI 를 사용하려면 `OCI_GENAI_ENDPOINT` 의 호스트만 교체하면
됩니다. `01_admin_setup.sql` 이 해당 호스트로 outbound HTTP ACE 를 자동 부여
합니다 (`DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE`).

## 7.3 실행

```bash
./run.sh vector-demo            # 풀 셋업 (01_admin → 06_test 전체)
```

비밀번호가 `.env` 에 비어 있으면 `run.sh` 가 ADB `ADMIN_PASSWORD` 와
`VECTOR_DEMO_PASSWORD` 를 프롬프트합니다.

세분화 옵션:

| 명령 | 동작 |
|---|---|
| `./run.sh vector-demo admin`   | 사용자 + ACL + ORDS schema enable 만 |
| `./run.sh vector-demo schema`  | 테이블/seed/ORDS 발행/SQL 검증 |
| `./run.sh vector-demo publish` | ORDS 모듈만 재발행 (handler PL/SQL 수정 후) |
| `./run.sh vector-demo test`    | SQL 레벨 검증만 |
| `./run.sh vector-demo onnx`    | (선택) `optional_load_onnx.sql` 로 ONNX 모델 로드 |
| `./run.sh vector-demo cleanup` | 99_cleanup.sql — 사용자/모델 전부 제거 |

## 7.4 REST 엔드포인트

발행되는 module 의 base path 는 `/ords/vector/docs/` 입니다.

### POST `/ords/vector/docs/search`

요청 body 스키마:

| 필드 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `q`  | string | (필수) | 검색 쿼리 텍스트 |
| `k`  | number | 5 | top-k 결과 수 |
| `by` | string | `"v4"` | `"v3"` 또는 `"v4"` — 어느 임베딩 컬럼으로 검색할지 |

요청 예:

```bash
# Cohere embed v4 (기본)
curl -sS -X POST http://<node>:8080/ords/vector/docs/search \
     -H 'Content-Type: application/json' \
     -d '{"q": "database REST API for web apps", "k": 5, "by": "v4"}'

# Cohere embed multilingual v3 (한국어 등 다국어 쿼리)
curl -sS -X POST http://<node>:8080/ords/vector/docs/search \
     -H 'Content-Type: application/json' \
     -d '{"q": "지하철 노선", "k": 3, "by": "v3"}'
```

응답 예시:

```json
{
  "query": "database REST API for web apps",
  "k": 5,
  "by": "v4",
  "results": [
    { "id": 2, "title": "ORDS overview",         "content": "...", "distance": 0.1283 },
    { "id": 1, "title": "Oracle ADB intro",      "content": "...", "distance": 0.2691 },
    { "id": 3, "title": "Vector search 23ai",    "content": "...", "distance": 0.3402 },
    { "id": 5, "title": "PostgreSQL pgvector",   "content": "...", "distance": 0.4115 },
    { "id": 6, "title": "Load balancer basics",  "content": "...", "distance": 0.5530 }
  ]
}
```

- `distance` 는 cosine 거리 (0 에 가까울수록 유사)
- `k` 생략 시 기본 5, `by` 생략 시 기본 `v4`
- `q` 누락 시 HTTP 400 + `{"error":"missing field q"}`
- `by` 값이 `v3` / `v4` 외이면 HTTP 400 + `{"error":"by must be v3 or v4"}`
- 핸들러는 검색 쿼리에 대해 `input_type=search_query` 로 GenAI 를 호출
  (적재 시점의 `search_document` 와 구분 — Cohere 권장 사용법)

### GET `/ords/vector/docs/`

모듈 사용법 안내 (JSON). 두 임베딩 모델명과 endpoint 목록 반환.

### GET `/ords/vector/docs/list`

현재 적재된 문서 목록 (id, title, dim_v3, dim_v4, created_at). ORDS
`collection_feed` source_type 이므로 `?limit=&offset=` 페이지네이션 가능.

### LB 경유 호출

`docs/04-ha.md` 절차로 OCI LB + TLS 가 구성된 상태라면:

```bash
curl -sS -X POST https://ords.example.com/ords/vector/docs/search \
     -H 'Content-Type: application/json' \
     -d '{"q": "particles quantum physics", "k": 3, "by": "v4"}'
```

## 7.5 SQL 레벨 직접 검증

ORDS 없이 SQL 만으로도 두 컬럼 검색 결과를 확인할 수 있습니다 (`06_test.sql`):

```sql
-- v4 로 검색
select id, title, distance
  from (
    select id, title,
           vector_distance(
             embedding_v4,
             q_emb_v4('pasta dish with eggs and cheese'),
             cosine
           ) as distance
      from doc_chunks
     where embedding_v4 is not null
     order by distance
     fetch first 3 rows only
  );
```

`q_emb_v3` / `q_emb_v4` 는 `06_test.sql` 이 세션 내에 생성하는 헬퍼 함수로,
내부적으로 `DBMS_VECTOR.UTL_TO_EMBEDDING` 을 `input_type=search_query` 로 호출
합니다.

## 7.6 두 모델 비교 관점

| 항목 | `embedding_v3` (cohere.embed-multilingual-v3.0) | `embedding_v4` (cohere.embed-v4.0) |
|---|---|---|
| 차원 | 1024 (고정) | 1024 (기본, 가변 가능 — truncation 지원) |
| 다국어 | 강함 (multilingual 학습) | v4 도 다국어 지원, retrieval 품질 개선 |
| input_type 구분 | 필수 (`search_document` / `search_query`) | 필수 |
| 비용/지연 | 토큰당 과금, REST 호출당 latency 발생 | 동일 (모델만 다름) |

같은 텍스트에 대해 두 컬럼을 나란히 두면, 핸들러 한 줄 변경 없이 `by` 파라미터
만으로 A/B 비교가 가능합니다.

## 7.7 (선택) ONNX in-DB 임베딩

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

## 7.8 보안 / 운영 고려사항

- 현재 모듈은 **익명 호출 허용** (`p_auto_rest_auth => false`). 운영 사용 시
  `ords.define_privilege` + role 매핑으로 OAuth2 토큰 또는 Basic 인증 강제
- GenAI 호출은 외부 API 이므로 토큰/요청 수에 대한 과금이 발생. handler 에 rate
  limit / quota 도입 권장 (예: APEX 의 throttle, ORDS `pre-hook` 등)
- `VECTOR_DISTANCE(..., cosine)` 는 정확검색이므로 데이터 규모 증가 시
  `04_seed.sql` 이 생성하는 NEIGHBOR PARTITIONS 인덱스 + `fetch approx first k`
  사용으로 전환 (handler 의 `order by ... fetch first` 절 수정)
- credential `OCI$RESOURCE_PRINCIPAL` 사용 시 ADB 의 Resource Principal 이
  필요한 IAM 정책 (`allow any-user to {GENERATIVE_AI_INFERENCE} in tenancy
  where ALL {request.principal.type = 'autonomousdatabase', ...}`) 이 있어야 함
- ACL: `01_admin_setup.sql` 은 `OCI_GENAI_ENDPOINT` 의 호스트만 부여. region 을
  바꿨다면 다시 실행되어야 함 (멱등하게 append 됨)

## 7.9 정리

```bash
./run.sh vector-demo cleanup
```

- `VECTOR_DEMO` 사용자 cascade drop → 테이블/인덱스/ORDS 메타 함께 제거
- ONNX 모델 `DOC_MODEL` 이 존재하면 함께 drop (없으면 skip)
- GenAI 호스트 ACE 는 다른 사용자에게 영향 줄 수 있어 그대로 둠
  (필요 시 `DBMS_NETWORK_ACL_ADMIN.REMOVE_HOST_ACE` 로 별도 제거)
