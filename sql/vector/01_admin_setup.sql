-- ============================================================
-- 01_admin_setup.sql
-- Connect as: ADMIN
--
-- 1) Vector 데모용 스키마/사용자 생성
-- 2) 필요한 권한 부여 (CONNECT/RESOURCE/DB_DEVELOPER_ROLE + DBMS_CLOUD)
-- 3) ORDS 스키마 활성화 (BASE_PATH = vector)
--
-- 멱등성: 사용자/권한 부여 모두 존재 시 무시(no-op)
-- ============================================================
set serveroutput on
set echo on
set define on
whenever sqlerror exit sql.sqlcode

-- run.sh 가 DEFINE 으로 주입
-- &VECTOR_DEMO_USER, &VECTOR_DEMO_PASSWORD

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
grant execute on dbms_cloud to &VECTOR_DEMO_USER;
grant execute on dbms_vector to &VECTOR_DEMO_USER;
grant execute on dbms_vector_chain to &VECTOR_DEMO_USER;

prompt -- 2b) OCI Generative AI 엔드포인트로 outbound HTTP ACL 부여
-- DBMS_VECTOR.UTL_TO_EMBEDDING 가 ocigenai provider 호출 시 필요.
-- 이미 같은 PRINCIPAL/HOST 조합이 있으면 APPEND_HOST_ACE 가 멱등하게 처리.
declare
  l_host varchar2(200) := regexp_substr('&OCI_GENAI_ENDPOINT', 'https?://([^/]+)', 1, 1, null, 1);
begin
  dbms_network_acl_admin.append_host_ace(
    host => l_host,
    ace  => xs$ace_type(
              privilege_list => xs$name_list('http'),
              principal_name => upper('&VECTOR_DEMO_USER'),
              principal_type => xs_acl.ptype_db)
  );
  commit;
  dbms_output.put_line('ACL granted: ' || upper('&VECTOR_DEMO_USER') || ' -> ' || l_host);
end;
/

prompt -- 2c) VECTOR_DEMO 스키마에 Resource Principal 활성화
-- OCI$RESOURCE_PRINCIPAL credential 은 호출 사용자의 스키마에 존재해야 함.
-- ADMIN 이 DBMS_CLOUD_ADMIN.ENABLE_RESOURCE_PRINCIPAL(username) 호출로
-- 대상 스키마에 RP credential 을 자동 생성/연결.
-- 단, ADB 의 Resource Principal 자체가 먼저 활성화되어 있어야 함
-- (안 되어 있으면 ENABLE_RESOURCE_PRINCIPAL() 인자 없이 한번 호출 필요).
begin
  begin
    dbms_cloud_admin.enable_resource_principal(username => upper('&VECTOR_DEMO_USER'));
    dbms_output.put_line('resource principal enabled for &VECTOR_DEMO_USER');
  exception
    when others then
      if sqlcode in (-20000, -20001, -20003) then
        -- ADB 전체에 RP 가 아직 enable 안 된 경우 — 먼저 켜고 다시 시도
        dbms_cloud_admin.enable_resource_principal;
        dbms_cloud_admin.enable_resource_principal(username => upper('&VECTOR_DEMO_USER'));
        dbms_output.put_line('ADB-level RP enabled, then &VECTOR_DEMO_USER RP enabled');
      else
        dbms_output.put_line('RP enable failed (continuing): ' || sqlerrm);
      end if;
  end;
  commit;
end;
/

prompt -- 3) ORDS 스키마 활성화 (BASE_PATH = vector)
declare
  l_enabled boolean := false;
begin
  -- 이미 활성화된 경우 pattern 으로 식별 (DBA_ORDS_SCHEMAS.PATTERN)
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
