-- ============================================================
-- 01_admin_setup.sql
-- Connect as: ADMIN
--
-- 1) Vector 데모용 스키마/사용자 생성
-- 2) 필요한 권한 부여 (CONNECT/RESOURCE/DB_DEVELOPER_ROLE + DBMS_VECTOR/_CHAIN)
-- 3) OCI GenAI inference 엔드포인트로 outbound network ACL 부여
-- 4) ORDS 스키마 활성화 (BASE_PATH = vector)
--
-- 멱등성: 사용자/권한/ACL 부여 모두 존재 시 skip
--
-- DEFINE: &VECTOR_DEMO_USER, &VECTOR_DEMO_PASSWORD, &OCI_GENAI_HOST
-- ============================================================
set serveroutput on
set echo on
set define on
whenever sqlerror exit sql.sqlcode

prompt -- 1) 사용자 생성 (이미 있으면 skip)
declare
  l_cnt number;
begin
  select count(*) into l_cnt
    from dba_users where username = upper('&VECTOR_DEMO_USER');
  if l_cnt = 0 then
    execute immediate 'create user &VECTOR_DEMO_USER identified by "&VECTOR_DEMO_PASSWORD"'
                   || ' default tablespace data quota unlimited on data';
    dbms_output.put_line('user &VECTOR_DEMO_USER created');
  else
    dbms_output.put_line('user &VECTOR_DEMO_USER already exists - skip');
  end if;
end;
/

prompt -- 2) 기본 권한
grant connect, resource to &VECTOR_DEMO_USER;
grant db_developer_role to &VECTOR_DEMO_USER;
grant create session, create table, create procedure, create view to &VECTOR_DEMO_USER;
grant execute on dbms_vector       to &VECTOR_DEMO_USER;   -- UTL_TO_EMBEDDING 호출용
grant execute on dbms_vector_chain to &VECTOR_DEMO_USER;   -- CREATE_CREDENTIAL 호출용

prompt -- 3) OCI GenAI inference 엔드포인트 outbound ACL (이미 있으면 skip 효과)
declare
begin
  dbms_network_acl_admin.append_host_ace(
    host => '&OCI_GENAI_HOST',
    ace  => xs$ace_type(
      privilege_list => xs$name_list('http', 'connect', 'resolve'),
      principal_name => upper('&VECTOR_DEMO_USER'),
      principal_type => xs_acl.ptype_db
    )
  );
  dbms_output.put_line('network ACE appended for host &OCI_GENAI_HOST principal &VECTOR_DEMO_USER');
exception
  when others then
    dbms_output.put_line('ACE append skipped/already present: ' || sqlerrm);
end;
/

prompt -- 4) ORDS 스키마 활성화 (BASE_PATH = vector)
declare
  l_enabled boolean := false;
begin
  for r in (
    select pattern
      from dba_ords_schemas
     where parsing_schema = upper('&VECTOR_DEMO_USER')
  ) loop
    dbms_output.put_line('ORDS already enabled for &VECTOR_DEMO_USER (pattern=' || r.pattern || ')');
    l_enabled := true;
  end loop;

  if not l_enabled then
    ords_admin.enable_schema(
      p_enabled             => true,
      p_schema              => upper('&VECTOR_DEMO_USER'),
      p_url_mapping_type    => 'BASE_PATH',
      p_url_mapping_pattern => 'vector',
      p_auto_rest_auth      => false
    );
    commit;
    dbms_output.put_line('ORDS enabled: schema=&VECTOR_DEMO_USER, base=/ords/vector/');
  end if;
end;
/

prompt -- 결과
column username       format a25
column account_status format a18
column pattern        format a20
select username, account_status from dba_users where username = upper('&VECTOR_DEMO_USER');
select parsing_schema, pattern
  from dba_ords_schemas where parsing_schema = upper('&VECTOR_DEMO_USER');

prompt -- 01_admin_setup done
exit
