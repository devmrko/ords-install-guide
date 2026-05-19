-- ============================================================
-- 02_credential.sql
-- Connect as: &VECTOR_DEMO_USER
--
-- DBMS_VECTOR_CHAIN.CREATE_CREDENTIAL 로 OCI GenAI 호출용 native credential
-- 생성. credential 은 호출 사용자(VECTOR_DEMO) 스키마에 만들어진다.
--   - user_ocid / tenancy_ocid / fingerprint / private_key (PEM body)
--   - private_key 는 -----BEGIN PRIVATE KEY----- / -----END PRIVATE KEY-----
--     줄과 모든 개행을 제거한 base64 본문만 전달해야 함
--   - 08_vector_demo.sh 가 .env 의 OCI_API_KEY_PEM 파일을 읽어 strip 후 DEFINE 으로 주입
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
  -- USER_CREDENTIALS 가 ADB 23ai 에서 노출됨. 없으면 drop 시 예외 처리
  begin
    execute immediate
      'select count(*) from user_credentials where credential_name = upper(:1)'
      into l_cnt using '&OCI_GENAI_CRED_NAME';
  exception
    when others then
      l_cnt := 0;
  end;

  if l_cnt > 0 then
    begin
      dbms_vector_chain.drop_credential(credential_name => '&OCI_GENAI_CRED_NAME');
      dbms_output.put_line('dropped existing credential &OCI_GENAI_CRED_NAME');
    exception
      when others then
        -- 일부 버전은 DBMS_CLOUD.DROP_CREDENTIAL 만 지원
        dbms_cloud.drop_credential(credential_name => '&OCI_GENAI_CRED_NAME');
        dbms_output.put_line('dropped existing credential via DBMS_CLOUD');
    end;
  end if;
end;
/

prompt -- 2) credential 생성
begin
  dbms_vector_chain.create_credential(
    credential_name => '&OCI_GENAI_CRED_NAME',
    params          => json(q'<{
      "user_ocid"       : "&OCI_USER_OCID",
      "tenancy_ocid"    : "&OCI_TENANCY_OCID",
      "compartment_ocid": "&OCI_COMPARTMENT_OCID",
      "private_key"     : "&OCI_PRIVATE_KEY",
      "fingerprint"     : "&OCI_KEY_FINGERPRINT"
    }>')
  );
  dbms_output.put_line('credential &OCI_GENAI_CRED_NAME created in schema &VECTOR_DEMO_USER');
end;
/

prompt -- 3) 결과 확인
column credential_name format a25
column username        format a25
column enabled         format a8
select credential_name, username, enabled
  from user_credentials
 where credential_name = upper('&OCI_GENAI_CRED_NAME');

prompt -- 02_credential done
exit
