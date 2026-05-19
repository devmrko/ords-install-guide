-- ============================================================
-- 02_credential.sql
-- Connect as: &VECTOR_DEMO_USER
--
-- DBMS_VECTOR.UTL_TO_EMBEDDING (provider=ocigenai) 호출용 OCI native
-- API key credential 을 등록.
--
-- 패키지 짝:
--   DBMS_VECTOR.UTL_TO_EMBEDDING  ←→  DBMS_VECTOR_CHAIN.CREATE_CREDENTIAL
--   (DBMS_CLOUD.CREATE_CREDENTIAL 로 만들면 lookup 실패)
--
-- 멱등성: 같은 이름의 credential 이 있으면 DROP 후 재생성
--
-- DEFINE: &OCI_GENAI_CRED_NAME, &OCI_USER_OCID, &OCI_TENANCY_OCID,
--         &OCI_COMPARTMENT_OCID, &OCI_KEY_FINGERPRINT, &OCI_PRIVATE_KEY
-- ============================================================
set serveroutput on
set echo on
set define on
set scan on
set sqlblanklines on
whenever sqlerror exit sql.sqlcode

prompt -- 1) 기존 credential 있으면 drop (재생성 위해)
declare
  l_cnt number;
begin
  begin
    execute immediate
      'select count(*) from user_credentials where credential_name = upper(:1)'
      into l_cnt using '&OCI_GENAI_CRED_NAME';
  exception
    when others then l_cnt := 0;
  end;

  if l_cnt > 0 then
    dbms_vector_chain.drop_credential(credential_name => '&OCI_GENAI_CRED_NAME');
    dbms_output.put_line('dropped existing credential &OCI_GENAI_CRED_NAME');
  end if;
end;
/

prompt -- 2) credential 생성  (보안: echo/termout off — private_key 가 로그에 안 박히게)
set echo off
set termout off
declare
  l_params clob;
begin
  l_params :=
    '{'                                                  ||
    '"user_ocid"       : "&OCI_USER_OCID",'              ||
    '"tenancy_ocid"    : "&OCI_TENANCY_OCID",'           ||
    '"compartment_ocid": "&OCI_COMPARTMENT_OCID",'       ||
    '"private_key"     : "&OCI_PRIVATE_KEY",'            ||
    '"fingerprint"     : "&OCI_KEY_FINGERPRINT"'         ||
    '}';
  dbms_vector_chain.create_credential(
    credential_name => '&OCI_GENAI_CRED_NAME',
    params          => json(l_params)
  );
end;
/

set termout on
set echo on
prompt -- (create_credential 완료 — 본문은 보안상 로그 미출력)

prompt -- 3) 결과 확인
column credential_name format a25
column username        format a25
column enabled         format a8
select credential_name, username, enabled
  from user_credentials
 where credential_name = upper('&OCI_GENAI_CRED_NAME');

prompt -- 02_credential done
exit
