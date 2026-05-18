-- ============================================================
-- smoke_test.sql
-- ORDS install 직후 기본 검증
-- ============================================================
set serveroutput on
set linesize 200
set pagesize 100

prompt -- 1) ORDS 메타데이터 스키마 존재 확인
select username, account_status
  from dba_users
 where username in ('ORDS_METADATA','ORDS_PUBLIC_USER')
 order by 1;

prompt -- 2) ORDS 버전
select ords.installed_version from dual;

prompt -- 3) enable 된 스키마 목록 (있으면 표시)
column parsing_schema format a25
column pattern        format a30
select parsing_schema, pattern
  from user_ords_schemas
 order by 1
 fetch first 20 rows only;

prompt -- 4) 풀(pool) 통계 — db_pool 별 active/total
select pool_name, in_use, total_size
  from v$ords_pool_stats
 order by 1
 fetch first 10 rows only;

prompt -- 끝
