-- ============================================================
-- 02_load_onnx.sql
-- Connect as: ADMIN
--
-- ONNX 임베딩 모델을 DB 안에 로드.
--   - Oracle 이 공개한 사전 가공된 all-MiniLM-L6-v2 (384-dim, augmented zip) 사용
--   - DBMS_CLOUD.GET_OBJECT 로 DATA_PUMP_DIR 에 다운로드
--   - DBMS_VECTOR.LOAD_ONNX_MODEL 로 모델 등록
--   - 데모 user 에 사용 권한 부여
--
-- 멱등성:
--   - 모델 이미 등록되어 있으면 skip
--   - 파일 이미 다운로드되어 있으면 skip
--
-- DEFINE: &VECTOR_DEMO_USER, &VECTOR_MODEL_NAME, &VECTOR_MODEL_URI, &VECTOR_MODEL_FILE
-- ============================================================
set serveroutput on
set echo on
set define on
whenever sqlerror exit sql.sqlcode

prompt -- 1) 모델 이미 등록되어 있는지 확인
declare
  l_cnt number;
begin
  select count(*) into l_cnt
    from user_mining_models where model_name = upper('&VECTOR_MODEL_NAME');
  if l_cnt > 0 then
    dbms_output.put_line('model &VECTOR_MODEL_NAME already loaded - skip download/load');
    -- 권한 부여만 다시 (멱등)
    execute immediate 'grant select, mining model on "&VECTOR_MODEL_NAME" to &VECTOR_DEMO_USER';
    dbms_output.put_line('grant mining model to &VECTOR_DEMO_USER done');
  else
    dbms_output.put_line('model not present - will download and load');
  end if;
end;
/

prompt -- 2) ONNX 파일 다운로드 (이미 있으면 GET_OBJECT 가 overwrite — 부담 없음)
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_mining_models
   where model_name = upper('&VECTOR_MODEL_NAME');
  if l_cnt > 0 then return; end if;

  dbms_output.put_line('downloading ONNX model from: &VECTOR_MODEL_URI');
  dbms_cloud.get_object(
    object_uri     => '&VECTOR_MODEL_URI',
    directory_name => 'DATA_PUMP_DIR',
    file_name      => '&VECTOR_MODEL_FILE'
  );
  dbms_output.put_line('downloaded to DATA_PUMP_DIR/&VECTOR_MODEL_FILE');
end;
/

prompt -- 3) 모델 로드 (augmented zip 직접 인식)
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_mining_models
   where model_name = upper('&VECTOR_MODEL_NAME');
  if l_cnt > 0 then return; end if;

  dbms_vector.load_onnx_model(
    directory  => 'DATA_PUMP_DIR',
    file_name  => '&VECTOR_MODEL_FILE',
    model_name => '&VECTOR_MODEL_NAME'
  );
  dbms_output.put_line('model loaded as &VECTOR_MODEL_NAME');
end;
/

prompt -- 4) 데모 user 에 mining model 사용 권한 부여 (멱등)
grant select, mining model on "&VECTOR_MODEL_NAME" to &VECTOR_DEMO_USER;

prompt -- 5) 모델 메타 확인
column model_name format a20
column algorithm  format a18
column mining_function format a18
select model_name, algorithm, mining_function
  from user_mining_models
 where model_name = upper('&VECTOR_MODEL_NAME');

prompt -- 임베딩 호출 자체가 동작하는지 1회 검증
column dim format 999
select vector_dimension_count(
         vector_embedding(&VECTOR_MODEL_NAME using 'hello world' as data)
       ) as dim
  from dual;

prompt -- 02_load_onnx done
exit
