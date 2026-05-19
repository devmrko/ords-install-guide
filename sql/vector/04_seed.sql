-- ============================================================
-- 04_seed.sql
-- Connect as: &VECTOR_DEMO_USER
--
-- 샘플 문서 12건 적재 + OCI GenAI Cohere v4 로 임베딩 자동 계산.
--
-- 호출 경로:
--   DBMS_VECTOR.UTL_TO_EMBEDDING(data, json(params))
--     params: provider=ocigenai, credential_name, url, model
--
-- 멱등성: title 기준으로 중복 행 INSERT skip.
--         기존 행도 embedding 이 NULL 이면 UPDATE 로 채움.
--
-- DEFINE: &OCI_GENAI_CRED_NAME, &OCI_GENAI_URL, &OCI_GENAI_MODEL
-- ============================================================
set serveroutput on
set echo on
set define on
whenever sqlerror exit sql.sqlcode

prompt -- 1) 임베딩 호출 헬퍼 (세션 종료 시 사라짐)
create or replace function emb(p_text clob) return vector authid current_user is
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
    t_row('Vector search 26ai',
          'Oracle Database 26ai introduces the VECTOR datatype and similarity search functions such as VECTOR_DISTANCE for AI workloads.'),
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
      insert into doc_chunks (title, content, embedding)
      values (
        l_data(i).title,
        l_data(i).body,
        emb(l_data(i).body)
      );
    else
      update doc_chunks
         set embedding = nvl(embedding, emb(content))
       where title = l_data(i).title;
    end if;
  end loop;
  commit;
end;
/

prompt -- 3) 적재 결과 — 임베딩 차원 확인
column id    format 999
column title format a25
column dim   format 9999
select id, title,
       vector_dimension_count(embedding) as dim
  from doc_chunks
 order by id;

prompt -- 4) 벡터 인덱스 생성 (이미 있으면 skip)
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_indexes where index_name = 'DOC_CHUNKS_EMB_IDX';
  if l_cnt = 0 then
    execute immediate
      'create vector index doc_chunks_emb_idx on doc_chunks (embedding)' ||
      ' organization neighbor partitions distance cosine with target accuracy 95';
    dbms_output.put_line('created index: doc_chunks_emb_idx');
  end if;
exception when others then
  dbms_output.put_line('skip index doc_chunks_emb_idx: ' || sqlerrm);
end;
/

prompt -- 04_seed done
exit
