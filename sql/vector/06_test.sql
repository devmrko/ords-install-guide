-- ============================================================
-- 06_test.sql
-- Connect as: &VECTOR_DEMO_USER
--
-- ORDS 거치지 않고 SQL 레벨에서 두 임베딩 컬럼 (v3 / v4) 이 정상 동작하는지 확인.
-- (REST 호출은 docs/07-vector-rest.md 의 curl 예제 참고)
--
-- DEFINE: &OCI_GENAI_CREDENTIAL, &OCI_GENAI_ENDPOINT,
--         &OCI_GENAI_MODEL_V3, &OCI_GENAI_MODEL_V4
-- ============================================================
set serveroutput on
set echo on
set define on
set linesize 200
set pagesize 100
whenever sqlerror exit sql.sqlcode

prompt -- 0) 적재 건수 + 두 컬럼 임베딩 차원
column rows_loaded format 9999
column dim_v3      format 9999
column dim_v4      format 9999
select count(*)                                       as rows_loaded,
       min(vector_dimension_count(embedding_v3))      as dim_v3,
       min(vector_dimension_count(embedding_v4))      as dim_v4
  from doc_chunks;

prompt -- 검색 쿼리용 임베딩 헬퍼 (input_type = search_query)
create or replace function q_emb_v3(p_text clob) return vector authid current_user is
  l_params json;
begin
  l_params := json('{
    "provider": "ocigenai",
    "credential_name": "&OCI_GENAI_CREDENTIAL",
    "url": "&OCI_GENAI_ENDPOINT",
    "model": "&OCI_GENAI_MODEL_V3",
    "input_type": "search_query"
  }');
  return dbms_vector.utl_to_embedding(p_text, l_params);
end;
/

create or replace function q_emb_v4(p_text clob) return vector authid current_user is
  l_params json;
begin
  l_params := json('{
    "provider": "ocigenai",
    "credential_name": "&OCI_GENAI_CREDENTIAL",
    "url": "&OCI_GENAI_ENDPOINT",
    "model": "&OCI_GENAI_MODEL_V4",
    "input_type": "search_query"
  }');
  return dbms_vector.utl_to_embedding(p_text, l_params);
end;
/

column title    format a25
column distance format 0.0000

prompt -- 1) "database REST API" — v3 top-5
select id, title, distance
  from (
    select id, title,
           vector_distance(embedding_v3, q_emb_v3('database REST API for web apps'), cosine) as distance
      from doc_chunks
     where embedding_v3 is not null
     order by distance
     fetch first 5 rows only
  );

prompt -- 2) "database REST API" — v4 top-5
select id, title, distance
  from (
    select id, title,
           vector_distance(embedding_v4, q_emb_v4('database REST API for web apps'), cosine) as distance
      from doc_chunks
     where embedding_v4 is not null
     order by distance
     fetch first 5 rows only
  );

prompt -- 3) "pasta dish with eggs and cheese" — v4 top-3
select id, title, distance
  from (
    select id, title,
           vector_distance(embedding_v4, q_emb_v4('pasta dish with eggs and cheese'), cosine) as distance
      from doc_chunks
     where embedding_v4 is not null
     order by distance
     fetch first 3 rows only
  );

prompt -- 4) "particles quantum physics" — v4 top-3
select id, title, distance
  from (
    select id, title,
           vector_distance(embedding_v4, q_emb_v4('particles quantum physics'), cosine) as distance
      from doc_chunks
     where embedding_v4 is not null
     order by distance
     fetch first 3 rows only
  );

prompt -- 5) 다국어 — 한국어 쿼리 → v3 (multilingual) top-3
-- v3 = cohere.embed-multilingual-v3.0 이므로 한국어 쿼리도 의미 매칭이 동작해야 함
select id, title, distance
  from (
    select id, title,
           vector_distance(embedding_v3, q_emb_v3('지하철 노선 네트워크'), cosine) as distance
      from doc_chunks
     where embedding_v3 is not null
     order by distance
     fetch first 3 rows only
  );

prompt -- 06_test done
exit
