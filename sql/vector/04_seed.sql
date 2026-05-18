-- ============================================================
-- 04_seed.sql
-- Connect as: &VECTOR_DEMO_USER
--
-- 샘플 문서 12건 적재 + 두 OCI GenAI Cohere 모델로 서버측 임베딩 자동 계산.
--   - embedding_v3 : cohere.embed-multilingual-v3.0 (1024-dim)
--   - embedding_v4 : cohere.embed-v4.0              (1024-dim 기본)
--
-- 멱등성: title 기준으로 중복 행 INSERT skip.
--         기존 행도 embedding_v3/v4 가 NULL 이면 UPDATE 로 채움.
--
-- DEFINE: &OCI_GENAI_CREDENTIAL, &OCI_GENAI_ENDPOINT,
--         &OCI_GENAI_MODEL_V3, &OCI_GENAI_MODEL_V4
-- ============================================================
set serveroutput on
set echo on
set define on
whenever sqlerror exit sql.sqlcode

prompt -- 1) 두 모델 호출용 JSON 파라미터 헬퍼 함수 (지역적 — 세션 종료 시 사라짐)
-- input_type 은 cohere 요구사항: 적재(문서)는 search_document, 검색(쿼리)은 search_query
create or replace function emb_v3(p_text clob, p_input_type varchar2 default 'search_document')
return vector authid current_user is
  l_params json;
begin
  l_params := json('{
    "provider": "ocigenai",
    "credential_name": "&OCI_GENAI_CREDENTIAL",
    "url": "&OCI_GENAI_ENDPOINT",
    "model": "&OCI_GENAI_MODEL_V3",
    "input_type": "' || p_input_type || '"
  }');
  return dbms_vector.utl_to_embedding(p_text, l_params);
end;
/

create or replace function emb_v4(p_text clob, p_input_type varchar2 default 'search_document')
return vector authid current_user is
  l_params json;
begin
  l_params := json('{
    "provider": "ocigenai",
    "credential_name": "&OCI_GENAI_CREDENTIAL",
    "url": "&OCI_GENAI_ENDPOINT",
    "model": "&OCI_GENAI_MODEL_V4",
    "input_type": "' || p_input_type || '"
  }');
  return dbms_vector.utl_to_embedding(p_text, l_params);
end;
/

prompt -- 2) 샘플 데이터 정의 + 적재
declare
  type t_row is record (
    title varchar2(200),
    body  varchar2(4000)
  );
  type t_rows is table of t_row;

  l_data t_rows := t_rows(
    t_row('Oracle ADB intro',
          'Oracle Autonomous Database is a fully managed cloud database service that automates patching, tuning, and backups for transactional and analytical workloads.'),
    t_row('ORDS overview',
          'Oracle REST Data Services exposes database tables and PL/SQL programs as REST endpoints, running as an embedded Jetty Java application.'),
    t_row('Vector search 23ai',
          'Oracle Database 23ai introduces the VECTOR datatype and similarity search functions such as VECTOR_DISTANCE for AI workloads.'),
    t_row('Sentence transformer',
          'all-MiniLM-L6-v2 is a small sentence transformer that produces 384 dimensional embeddings suitable for semantic similarity search.'),
    t_row('PostgreSQL pgvector',
          'pgvector is a PostgreSQL extension that adds a vector type and approximate nearest neighbor indexing for embedding search.'),
    t_row('Load balancer basics',
          'A network load balancer distributes incoming requests across backend servers to improve availability and horizontal scalability.'),
    t_row('TLS termination',
          'Terminating TLS at a load balancer lets backend services handle plain HTTP and centralizes certificate management.'),
    t_row('Kubernetes pods',
          'In Kubernetes a pod groups one or more containers that share networking and storage and represent the smallest deployable unit.'),
    t_row('Recipe carbonara',
          'Pasta alla carbonara combines spaghetti, guanciale, eggs, pecorino romano cheese, and black pepper without any cream.'),
    t_row('Seoul subway',
          'The Seoul metropolitan subway network operates more than twenty lines and is one of the longest urban rail systems in the world.'),
    t_row('Photosynthesis',
          'Photosynthesis converts light energy into chemical energy stored in glucose, releasing oxygen as a byproduct in plant chloroplasts.'),
    t_row('Quantum entanglement',
          'Quantum entanglement is a physical phenomenon where pairs of particles share states in a way that measurement of one instantly determines the other.')
  );

  l_cnt number;
begin
  for i in 1 .. l_data.count loop
    select count(*) into l_cnt from doc_chunks where title = l_data(i).title;
    if l_cnt = 0 then
      insert into doc_chunks (title, content, embedding_v3, embedding_v4)
      values (
        l_data(i).title,
        l_data(i).body,
        emb_v3(l_data(i).body),
        emb_v4(l_data(i).body)
      );
    else
      -- 기존 행이 NULL 임베딩이면 백필
      update doc_chunks
         set embedding_v3 = nvl(embedding_v3, emb_v3(content)),
             embedding_v4 = nvl(embedding_v4, emb_v4(content))
       where title = l_data(i).title;
    end if;
  end loop;
  commit;
end;
/

prompt -- 3) 적재 결과 — 두 모델의 임베딩 차원이 정상인지 확인
column id      format 999
column title   format a25
column dim_v3  format 999
column dim_v4  format 999
select id, title,
       vector_dimension_count(embedding_v3) as dim_v3,
       vector_dimension_count(embedding_v4) as dim_v4
  from doc_chunks
 order by id;

prompt -- 4) 벡터 인덱스 생성 (이미 있으면 skip)
declare
  procedure ensure_vidx(p_idx varchar2, p_col varchar2) is
    l_cnt number;
  begin
    select count(*) into l_cnt from user_indexes where index_name = upper(p_idx);
    if l_cnt = 0 then
      execute immediate
        'create vector index ' || p_idx ||
        ' on doc_chunks (' || p_col || ')' ||
        ' organization neighbor partitions distance cosine with target accuracy 95';
      dbms_output.put_line('created index: ' || p_idx);
    end if;
  exception when others then
    dbms_output.put_line('skip index ' || p_idx || ': ' || sqlerrm);
  end;
begin
  ensure_vidx('doc_chunks_v3_idx', 'embedding_v3');
  ensure_vidx('doc_chunks_v4_idx', 'embedding_v4');
end;
/

prompt -- 04_seed done
exit
