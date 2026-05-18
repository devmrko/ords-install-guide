-- ============================================================
-- 06_test.sql
-- Connect as: &VECTOR_DEMO_USER
--
-- ORDS 거치지 않고 SQL 레벨에서 벡터 검색이 정상 동작하는지 확인.
-- (REST 호출은 docs/07-vector-rest.md 의 curl 예제 참고)
-- DEFINE: &VECTOR_MODEL_NAME
-- ============================================================
set serveroutput on
set echo on
set define on
set linesize 200
set pagesize 100
whenever sqlerror exit sql.sqlcode

prompt -- 1) 적재 건수 + 임베딩 차원
column dim format 999
select count(*) as rows_loaded,
       min(vector_dimension_count(embedding)) as dim
  from doc_chunks;

prompt -- 2) "database REST API" 의도와 가까운 top-5
column title format a25
column distance format 0.0000
select id, title, distance
  from (
    select id, title,
           vector_distance(
             embedding,
             vector_embedding(&VECTOR_MODEL_NAME using 'database REST API for web apps' as data),
             cosine
           ) as distance
      from doc_chunks
     order by distance
     fetch first 5 rows only
  );

prompt -- 3) "pasta dish with eggs and cheese" 의도와 가까운 top-3
select id, title, distance
  from (
    select id, title,
           vector_distance(
             embedding,
             vector_embedding(&VECTOR_MODEL_NAME using 'pasta dish with eggs and cheese' as data),
             cosine
           ) as distance
      from doc_chunks
     order by distance
     fetch first 3 rows only
  );

prompt -- 4) "particles quantum physics" 의도와 가까운 top-3
select id, title, distance
  from (
    select id, title,
           vector_distance(
             embedding,
             vector_embedding(&VECTOR_MODEL_NAME using 'particles quantum physics' as data),
             cosine
           ) as distance
      from doc_chunks
     order by distance
     fetch first 3 rows only
  );

prompt -- 06_test done
exit
