# 07. Vector + ORDS REST 데모

기존에 설치된 ORDS + ADB 환경 위에 **벡터 임베딩 + 유사도 검색 REST API** 를
한 번에 발행하는 데모입니다. 단일 명령으로 다음 작업을 수행합니다.

1. ADMIN 으로 데모 스키마(`VECTOR_DEMO`) 생성 및 ORDS 활성화
2. ADMIN 으로 Oracle 이 공개한 ONNX 임베딩 모델 (`all-MiniLM-L6-v2`, 384차원) 을
   ADB 안에 로드
3. 데모 스키마에 `VECTOR(384, FLOAT32)` 컬럼을 가진 `DOC_CHUNKS` 테이블 생성
4. 12건의 샘플 문장 적재 (서버측 `VECTOR_EMBEDDING()` 으로 임베딩 자동 계산)
5. ORDS module `vector.search` + template + handler 발행
6. SQL 레벨에서 검색 결과를 확인

## 7.1 사전 요구사항

- ORDS 노드에서 `./run.sh all` 이 이미 완료된 상태
- ADB 가 **Oracle Database 23ai** 기반이어야 함 (`VECTOR` 타입 / `DBMS_VECTOR`
  / `VECTOR_EMBEDDING` 등 23ai 이상 기능 사용)
- `DATA_PUMP_DIR` 가 비어있을 필요는 없음 (다운로드 시 동일 이름 파일이 있으면
  덮어씀)
- 인터넷 egress 가 ADB 에서 가능 (PAR URL 접근). 폐쇄망 ADB 면 §7.6 참고

## 7.2 `.env` 설정

```bash
VECTOR_DEMO_USER=VECTOR_DEMO
VECTOR_DEMO_PASSWORD=                       # ADB 비밀번호 정책: 12~30자, 대/소/숫자/특수
VECTOR_MODEL_NAME=DOC_MODEL
VECTOR_MODEL_URI=https://adwc4pm.objectstorage.us-ashburn-1.oci.customer-oci.com/p/.../all_MiniLM_L6_v2_augmented.zip
VECTOR_MODEL_FILE=all_MiniLM_L6_v2_augmented.zip
```

`VECTOR_MODEL_URI` 기본값은 Oracle 공식 OML-Resources 버킷의 공개 PAR 입니다.
변경이 필요한 경우 자체 변환한 ONNX (`.onnx` 또는 augmented `.zip`) 을 OCI Object
Storage 에 올린 뒤 PAR URL 로 노출하여 두 변수만 교체하면 됩니다.

## 7.3 실행

```bash
./run.sh vector-demo            # 풀 셋업 (01_admin → 06_test 전체)
```

비밀번호가 `.env` 에 비어 있으면 `run.sh` 가 `ADB ADMIN_PASSWORD` 와
`VECTOR_DEMO_PASSWORD` 를 프롬프트합니다.

세분화 옵션:

| 명령 | 동작 |
|---|---|
| `./run.sh vector-demo admin`   | 사용자 생성 + ORDS 활성화만 |
| `./run.sh vector-demo onnx`    | ONNX 모델 로드만 (시간이 가장 오래 걸리는 단계) |
| `./run.sh vector-demo schema`  | 테이블/seed/ORDS 발행/SQL 검증 |
| `./run.sh vector-demo publish` | ORDS 모듈만 재발행 (handler PL/SQL 수정 후) |
| `./run.sh vector-demo test`    | SQL 레벨 검증만 |
| `./run.sh vector-demo cleanup` | 99_cleanup.sql — 사용자/모델 전부 제거 |

## 7.4 REST 엔드포인트

발행되는 module 의 base path 는 `/ords/vector/docs/` 입니다.

### POST `/ords/vector/docs/search`

요청:

```bash
curl -sS -X POST http://<node>:8080/ords/vector/docs/search \
     -H 'Content-Type: application/json' \
     -d '{"q": "database REST API for web apps", "k": 5}'
```

응답 예시:

```json
{
  "query": "database REST API for web apps",
  "k": 5,
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
- `k` 생략 시 기본 5
- `q` 누락 시 HTTP 400 + `{"error":"missing field q"}`

### GET `/ords/vector/docs/`

모듈 사용법 안내 (JSON).

### GET `/ords/vector/docs/list`

현재 적재된 문서 목록 (id, title, dim, created_at). ORDS `collection_feed`
source_type 이므로 `?limit=&offset=` 페이지네이션 가능.

### LB 경유 호출

`docs/04-ha.md` 절차로 OCI LB + TLS 가 구성된 상태라면:

```bash
curl -sS -X POST https://ords.example.com/ords/vector/docs/search \
     -H 'Content-Type: application/json' \
     -d '{"q": "particles quantum physics", "k": 3}'
```

## 7.5 SQL 레벨 직접 검증

ORDS 없이 SQL 만으로도 검색 결과를 확인할 수 있습니다 (`06_test.sql` 내용):

```sql
select id, title, distance
  from (
    select id, title,
           vector_distance(
             embedding,
             vector_embedding(DOC_MODEL using 'pasta dish with eggs and cheese' as data),
             cosine
           ) as distance
      from doc_chunks
     order by distance
     fetch first 3 rows only
  );
```

기대 결과:

```
ID  TITLE                      DISTANCE
--- ------------------------- --------
  9 Recipe carbonara            0.1742
  4 Sentence transformer        0.5891
  1 Oracle ADB intro            0.6438
```

## 7.6 폐쇄망 ADB 에서 모델 로드

ADB 가 인터넷 egress 가 불가한 경우 PAR URL 접근이 실패합니다. 대안:

1. 인터넷이 되는 워크스테이션에서 ONNX 파일 직접 다운로드
2. 사용자의 OCI Object Storage 사설 버킷에 업로드
3. 같은 tenancy 의 ADB 라면 OCI resource principal 또는 OCI native credential
   로 접근 가능
4. `.env` 의 `VECTOR_MODEL_URI` 를 사설 PAR 또는 native URL 로 교체

또는 SQL Developer 에서 ONNX 파일을 BLOB 컬럼에 직접 적재한 뒤
`DBMS_VECTOR.LOAD_ONNX_MODEL` 의 BLOB 오버로드를 사용하는 방법도 있습니다.

## 7.7 임베딩 모델 교체

`all-MiniLM-L6-v2` 외의 다른 sentence-transformer 모델을 쓰려면:

1. HuggingFace 등에서 모델 다운로드
2. Oracle 이 제공하는 변환 스크립트로 augmented ONNX zip 으로 변환
   (참고: `OML4Py` 의 `EmbeddingModel` 클래스)
3. OCI Object Storage 에 업로드 → PAR 생성
4. `.env` 의 `VECTOR_MODEL_URI` 교체
5. `sql/vector/03_schema.sql` 의 `VECTOR(384, FLOAT32)` 차원을 모델 출력에 맞춰 수정
6. `./run.sh vector-demo cleanup && ./run.sh vector-demo`

## 7.8 보안 / 운영 고려사항

- 현재 모듈은 **익명 호출 허용** (`p_auto_rest_auth => false`). 운영 사용 시
  `ords.define_privilege` + role 매핑으로 OAuth2 토큰 또는 Basic 인증 강제
- `DOC_CHUNKS` 적재 함수가 `RESOURCE` 권한 기반이므로, 운영에서는 별도 ETL
  파이프라인 + 적재 전용 PL/SQL API 권장
- `VECTOR_DISTANCE(..., cosine)` 는 정확검색이므로 데이터 규모 증가 시
  `vector_distance(... approximate)` + 벡터 인덱스 활용 필요
  (`03_schema.sql` 의 IVF 인덱스 + `fetch approx first k rows only` 사용)
- 임베딩 모델은 라이선스 확인 필수. all-MiniLM-L6-v2 는 Apache 2.0

## 7.9 정리

```bash
./run.sh vector-demo cleanup
```

- `VECTOR_DEMO` 사용자 cascade drop → 테이블/인덱스/ORDS 메타 함께 제거
- `DOC_MODEL` ONNX 모델 drop
- `DATA_PUMP_DIR` 안의 zip 파일은 재사용 가능하도록 남겨둠
