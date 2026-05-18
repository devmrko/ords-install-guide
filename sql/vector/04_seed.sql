-- ============================================================
-- 04_seed.sql
-- Connect as: &VECTOR_DEMO_USER
--
-- 샘플 문서 12건을 적재. embedding 컬럼은 VECTOR_EMBEDDING() 으로
-- 서버 측에서 자동 계산 (DOC_MODEL 사용).
--
-- 멱등성: 같은 title 로 적재된 row 가 있으면 skip
-- DEFINE: &VECTOR_MODEL_NAME
-- ============================================================
set serveroutput on
set echo on
set define on
whenever sqlerror exit sql.sqlcode

prompt -- 1) 기존 행 수 확인
select count(*) as existing_rows from doc_chunks;

prompt -- 2) 샘플 적재 (중복 방지 — title 기준)
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
      execute immediate
        'insert into doc_chunks (title, content, embedding) ' ||
        'values (:1, :2, vector_embedding(' || '&VECTOR_MODEL_NAME' || ' using :3 as data))'
        using l_data(i).title, l_data(i).body, l_data(i).body;
    end if;
  end loop;
  commit;
end;
/

prompt -- 3) 적재 결과
column id    format 999
column title format a25
column dim   format 999
select id, title, vector_dimension_count(embedding) as dim
  from doc_chunks
 order by id;

prompt -- 4) (옵션) 인덱스가 03 단계에서 누락되었다면 지금 만든다 (데이터 있는 상태)
declare
  l_cnt number;
begin
  select count(*) into l_cnt from user_indexes where index_name = 'DOC_CHUNKS_EMB_IDX';
  if l_cnt = 0 then
    execute immediate q'[
      create vector index doc_chunks_emb_idx
        on doc_chunks (embedding)
        organization neighbor partitions
        distance cosine
        with target accuracy 95
    ]';
    dbms_output.put_line('vector index created (after seed)');
  end if;
end;
/

prompt -- 04_seed done
exit
