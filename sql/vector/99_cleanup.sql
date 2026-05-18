-- ============================================================
-- 99_cleanup.sql
-- Connect as: ADMIN
--
-- 벡터 데모로 생성된 리소스를 전부 제거.
--   - VECTOR_DEMO 사용자 (CASCADE — 테이블/인덱스/ORDS 메타 동반 삭제)
--   - DOC_MODEL ONNX 모델
--   - (DATA_PUMP_DIR 안의 다운로드 zip 은 남겨둠 — 다음 재설치 시 재사용)
--
-- DEFINE: &VECTOR_DEMO_USER, &VECTOR_MODEL_NAME
-- ============================================================
set serveroutput on
set echo on
set define on

prompt -- 1) ORDS 스키마 비활성화 (사용자 drop 전에)
declare
  l_cnt number;
begin
  select count(*) into l_cnt
    from dba_ords_schemas where parsing_schema = upper('&VECTOR_DEMO_USER');
  if l_cnt > 0 then
    ords_admin.enable_schema(
      p_enabled => false,
      p_schema  => upper('&VECTOR_DEMO_USER')
    );
    commit;
    dbms_output.put_line('ORDS schema disabled for &VECTOR_DEMO_USER');
  else
    dbms_output.put_line('ORDS schema mapping not present - skip');
  end if;
exception
  when others then
    dbms_output.put_line('ORDS disable failed (continuing): ' || sqlerrm);
end;
/

prompt -- 2) 사용자 drop
declare
  l_cnt number;
begin
  select count(*) into l_cnt from dba_users where username = upper('&VECTOR_DEMO_USER');
  if l_cnt > 0 then
    execute immediate 'drop user &VECTOR_DEMO_USER cascade';
    dbms_output.put_line('user &VECTOR_DEMO_USER dropped');
  else
    dbms_output.put_line('user &VECTOR_DEMO_USER not present - skip');
  end if;
end;
/

prompt -- 3) ONNX 모델 drop
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_mining_models
   where model_name = upper('&VECTOR_MODEL_NAME');
  if l_cnt > 0 then
    dbms_vector.drop_onnx_model(model_name => '&VECTOR_MODEL_NAME');
    dbms_output.put_line('model &VECTOR_MODEL_NAME dropped');
  else
    dbms_output.put_line('model &VECTOR_MODEL_NAME not present - skip');
  end if;
exception
  when others then
    -- 일부 ADB 버전은 DBMS_DATA_MINING.DROP_MODEL 만 지원
    begin
      execute immediate 'begin dbms_data_mining.drop_model(model_name => :1); end;'
        using '&VECTOR_MODEL_NAME';
      dbms_output.put_line('model &VECTOR_MODEL_NAME dropped (via dbms_data_mining)');
    exception
      when others then
        dbms_output.put_line('model drop failed: ' || sqlerrm);
    end;
end;
/

prompt -- 99_cleanup done
exit
