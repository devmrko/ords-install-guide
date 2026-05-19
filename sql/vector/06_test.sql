-- ============================================================
-- 06_test.sql
-- Connect as: &VECTOR_DEMO_USER
--
-- ORDS 거치지 않고 SQL 레벨에서 임베딩 컬럼이 정상 동작하는지 확인.
-- (REST 호출은 docs/07-vector-rest.md 의 curl 예제 참고)
--
-- DEFINE: &OCI_GENAI_CRED_NAME, &OCI_GENAI_URL, &OCI_GENAI_MODEL
-- ============================================================
set serveroutput on
set echo on
set define on
set linesize 200
set pagesize 100
whenever sqlerror exit sql.sqlcode

prompt -- 0) 적재 건수 + 임베딩 차원
column rows_loaded format 9999
column dim         format 9999
select count(*)                                as rows_loaded,
       min(vector_dimension_count(embedding))  as dim
  from doc_chunks;

prompt -- 검색 쿼리용 임베딩 헬퍼 (DBMS_VECTOR.UTL_TO_EMBEDDING)
create or replace function q_emb(p_text clob) return vector authid current_user is
  l_params clob;
begin
  l_params :=
    '{' ||
    '"provider"       : "ocigenai",'                       ||
    '"credential_name": "&OCI_GENAI_CRED_NAME",'           ||
    '"url"            : "&OCI_GENAI_URL",'                 ||
    '"model"          : "&OCI_GENAI_MODEL"'                ||
    '}';
  return dbms_vector.utl_to_embedding(p_text, json(l_params));
end;
/

column title    format a25
column distance format 0.0000

prompt -- 1) "database REST API" — top-5
select id, title, distance
  from (
    select id, title,
           vector_distance(embedding, q_emb('database REST API for web apps'), cosine) as distance
      from doc_chunks
     where embedding is not null
     order by distance
     fetch first 5 rows only
  );

prompt -- 2) "pasta dish with eggs and cheese" — top-3
select id, title, distance
  from (
    select id, title,
           vector_distance(embedding, q_emb('pasta dish with eggs and cheese'), cosine) as distance
      from doc_chunks
     where embedding is not null
     order by distance
     fetch first 3 rows only
  );

prompt -- 3) "particles quantum physics" — top-3
select id, title, distance
  from (
    select id, title,
           vector_distance(embedding, q_emb('particles quantum physics'), cosine) as distance
      from doc_chunks
     where embedding is not null
     order by distance
     fetch first 3 rows only
  );

prompt -- 4) 다국어 — 한국어 쿼리 (cohere.embed-v4.0 은 multilingual)
select id, title, distance
  from (
    select id, title,
           vector_distance(embedding, q_emb('지하철 노선 네트워크'), cosine) as distance
      from doc_chunks
     where embedding is not null
     order by distance
     fetch first 3 rows only
  );

prompt -- 06_test done
exit
