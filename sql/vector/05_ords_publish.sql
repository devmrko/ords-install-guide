-- ============================================================
-- 05_ords_publish.sql
-- Connect as: &VECTOR_DEMO_USER
--
-- 이 스키마 소유 ORDS module/template/handler 를 정의.
--   - module 'vector.search'   base_path = docs/
--   - template 'search' POST  → 텍스트 쿼리 → top-k 벡터 유사 문서
--                               body {"q": "...", "k": 5, "by": "v3" | "v4"}
--   - template ''       GET   → 모듈 사용법 안내(JSON)
--   - template 'list'   GET   → 적재된 문서 목록 (collection feed)
--
-- 호출 URL (LB 종단 가정):
--   POST  https://<host>/ords/vector/docs/search
--         body: {"q": "...", "k": 5, "by": "v4"}
--   GET   https://<host>/ords/vector/docs/
--   GET   https://<host>/ords/vector/docs/list
--
-- 멱등성: 같은 module/template/handler 정의는 ORDS API 가 update 수행
-- DEFINE: &OCI_GENAI_CRED_NAME, &OCI_GENAI_ENDPOINT,
--         &OCI_GENAI_MODEL_V3, &OCI_GENAI_MODEL_V4
--
-- 주의:
--   - sqlplus 'set define on' 이 기본이므로 q'~...~' 블록 안에서도
--     &VAR 가 PL/SQL 본문에 박힌 채로 ORDS 메타에 저장됨
--     (런타임에 credential/endpoint/model 식별자가 literal 로 사용됨)
-- ============================================================
set serveroutput on
set echo on
set define on
whenever sqlerror exit sql.sqlcode

prompt -- 1) module 정의
begin
  ords.define_module(
    p_module_name    => 'vector.search',
    p_base_path      => 'docs/',
    p_items_per_page => 25,
    p_status         => 'PUBLISHED',
    p_comments       => 'Vector similarity search demo over doc_chunks (Cohere v3/v4)'
  );
  commit;
end;
/

prompt -- 2) POST /docs/search  — 쿼리 텍스트로 top-k 벡터 유사 문서 반환
begin
  ords.define_template(
    p_module_name => 'vector.search',
    p_pattern     => 'search',
    p_priority    => 0,
    p_comments    => 'POST {q, k, by} -> top-k similar docs'
  );

  ords.define_handler(
    p_module_name    => 'vector.search',
    p_pattern        => 'search',
    p_method         => 'POST',
    p_source_type    => ords.source_type_plsql,
    p_mimes_allowed  => 'application/json',
    p_comments       => 'JSON in, JSON out. by=v3|v4 selects embedding column.',
    p_source         => q'~
declare
  l_body  clob   := :body_text;
  l_q     clob;
  l_k     number := 5;
  l_by    varchar2(8) := 'v4';
  l_qvec  vector;
  l_out   clob;
  l_params json;
begin
  if l_body is null or dbms_lob.getlength(l_body) = 0 then
    owa_util.status_line(400, 'Bad Request');
    owa_util.mime_header('application/json', false);
    owa_util.http_header_close;
    htp.p('{"error":"empty body. expected {q, k, by}"}');
    return;
  end if;

  l_q  := json_value(l_body, '$.q'  returning clob);
  l_k  := nvl(json_value(l_body, '$.k'  returning number), 5);
  l_by := lower(nvl(json_value(l_body, '$.by' returning varchar2), 'v4'));

  if l_q is null then
    owa_util.status_line(400, 'Bad Request');
    owa_util.mime_header('application/json', false);
    owa_util.http_header_close;
    htp.p('{"error":"missing field q"}');
    return;
  end if;

  if l_by not in ('v3','v4') then
    owa_util.status_line(400, 'Bad Request');
    owa_util.mime_header('application/json', false);
    owa_util.http_header_close;
    htp.p('{"error":"by must be v3 or v4"}');
    return;
  end if;

  -- 검색 쿼리는 input_type=search_query 사용 (Cohere 요구사항)
  if l_by = 'v3' then
    l_params := json('{
      "provider": "ocigenai",
      "credential_name": "&OCI_GENAI_CRED_NAME",
      "url": "&OCI_GENAI_ENDPOINT",
      "model": "&OCI_GENAI_MODEL_V3",
      "input_type": "search_query"
    }');
  else
    l_params := json('{
      "provider": "ocigenai",
      "credential_name": "&OCI_GENAI_CRED_NAME",
      "url": "&OCI_GENAI_ENDPOINT",
      "model": "&OCI_GENAI_MODEL_V4",
      "input_type": "search_query"
    }');
  end if;

  l_qvec := dbms_vector.utl_to_embedding(l_q, l_params);

  if l_by = 'v3' then
    select json_object(
             'query'   value l_q,
             'k'       value l_k,
             'by'      value l_by,
             'results' value json_arrayagg(
               json_object(
                 'id'       value id,
                 'title'    value title,
                 'content'  value content,
                 'distance' value distance
               ) order by distance
               returning clob
             )
             returning clob
           )
      into l_out
      from (
        select id, title, content,
               vector_distance(embedding_v3, l_qvec, cosine) as distance
          from doc_chunks
         where embedding_v3 is not null
         order by vector_distance(embedding_v3, l_qvec, cosine)
         fetch first l_k rows only
      );
  else
    select json_object(
             'query'   value l_q,
             'k'       value l_k,
             'by'      value l_by,
             'results' value json_arrayagg(
               json_object(
                 'id'       value id,
                 'title'    value title,
                 'content'  value content,
                 'distance' value distance
               ) order by distance
               returning clob
             )
             returning clob
           )
      into l_out
      from (
        select id, title, content,
               vector_distance(embedding_v4, l_qvec, cosine) as distance
          from doc_chunks
         where embedding_v4 is not null
         order by vector_distance(embedding_v4, l_qvec, cosine)
         fetch first l_k rows only
      );
  end if;

  owa_util.mime_header('application/json', false);
  owa_util.http_header_close;
  htp.prn(l_out);
exception
  when others then
    owa_util.status_line(500, 'Internal Server Error');
    owa_util.mime_header('application/json', false);
    owa_util.http_header_close;
    htp.p('{"error":"' || replace(sqlerrm, '"', '\"') || '"}');
end;
~'
  );
  commit;
end;
/

prompt -- 3) GET /docs/  — 사용법 안내
begin
  ords.define_template(
    p_module_name => 'vector.search',
    p_pattern     => '',
    p_priority    => 0,
    p_comments    => 'GET -> API usage hint'
  );

  ords.define_handler(
    p_module_name    => 'vector.search',
    p_pattern        => '',
    p_method         => 'GET',
    p_source_type    => ords.source_type_plsql,
    p_source         => q'~
begin
  owa_util.mime_header('application/json', false);
  owa_util.http_header_close;
  htp.p('{');
  htp.p('  "module": "vector.search",');
  htp.p('  "embeddings": {');
  htp.p('    "v3": "cohere.embed-multilingual-v3.0 (1024-dim)",');
  htp.p('    "v4": "cohere.embed-v4.0 (1024-dim default)"');
  htp.p('  },');
  htp.p('  "endpoints": [');
  htp.p('    {"method": "POST", "path": "search", "body": {"q": "text", "k": 5, "by": "v4"}, "desc": "top-k similar docs; by selects embedding column"},');
  htp.p('    {"method": "GET",  "path": "list",                                              "desc": "list indexed docs"}');
  htp.p('  ]');
  htp.p('}');
end;
~'
  );
  commit;
end;
/

prompt -- 4) GET /docs/list  — 적재된 문서 ID/title 나열
begin
  ords.define_template(
    p_module_name => 'vector.search',
    p_pattern     => 'list',
    p_priority    => 0,
    p_comments    => 'GET -> indexed doc list'
  );

  ords.define_handler(
    p_module_name    => 'vector.search',
    p_pattern        => 'list',
    p_method         => 'GET',
    p_source_type    => ords.source_type_collection_feed,
    p_items_per_page => 50,
    p_source         => q'~
      select id, title,
             vector_dimension_count(embedding_v3) as dim_v3,
             vector_dimension_count(embedding_v4) as dim_v4,
             created_at
        from doc_chunks
       order by id
    ~'
  );
  commit;
end;
/

prompt -- 5) 결과 메타 확인
column module_name  format a18
column uri_prefix   format a14
column status       format a10
select module_name, uri_prefix, status
  from user_ords_modules
 where module_name = 'vector.search';

column uri_template format a14
column method       format a8
column source_type  format a22
select t.uri_template, h.method, h.source_type
  from user_ords_handlers h
  join user_ords_templates t on t.id = h.template_id
 where t.module_name = 'vector.search'
 order by 1, 2;

prompt -- 05_ords_publish done
exit
