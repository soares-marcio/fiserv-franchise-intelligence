SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activation_proposals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activation_proposals (
    id bigint NOT NULL,
    channel_id bigint NOT NULL,
    company_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    data_afiliacao date,
    data_ativacao date,
    data_instalacao date,
    data_proposta date,
    establishment_id bigint,
    faturamento_anual_previsto numeric(18,2),
    hierarquia_origem character varying,
    import_batch_id bigint NOT NULL,
    nome_fantasia character varying,
    nr_da_proposta character varying NOT NULL,
    razao_social character varying,
    status_proposta character varying,
    sub_channel_id bigint NOT NULL,
    ticket_medio numeric(18,2),
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: activation_proposals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.activation_proposals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: activation_proposals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.activation_proposals_id_seq OWNED BY public.activation_proposals.id;


--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: establishments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.establishments (
    id bigint NOT NULL,
    channel_id bigint NOT NULL,
    company_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    duplicate_confirmed_at timestamp(6) without time zone,
    duplicate_confirmed_by character varying,
    duplicate_reason character varying,
    ec character varying(8) NOT NULL,
    primary_establishment_id bigint,
    updated_at timestamp(6) without time zone NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    CONSTRAINT establishments_ec_format CHECK (((ec)::text ~ '^[0-9]{8}$'::text)),
    CONSTRAINT establishments_not_self_primary CHECK (((primary_establishment_id IS NULL) OR (primary_establishment_id <> id)))
);


--
-- Name: map_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.map_snapshots (
    id bigint NOT NULL,
    agenda_semanal character varying,
    ativo_mes_atual boolean,
    ativo_ultimo_mes boolean,
    ativo_ultimos_30_dias boolean,
    cep character varying,
    channel_id bigint NOT NULL,
    cidade character varying,
    cluster_queda_fat character varying,
    cnae_codigo character varying,
    cnae_descricao character varying,
    created_at timestamp(6) without time zone NOT NULL,
    data_ativacao date,
    data_credenciamento date,
    data_instalacao date,
    data_suspensao date,
    data_ult_transacao date,
    diferenca_fat_m1_m2 numeric(18,2),
    diferenca_fat_pct numeric(12,4),
    endereco character varying,
    establishment_id bigint NOT NULL,
    estado character varying,
    faturamento_medio_3m numeric(18,2),
    hierarquia_origem character varying,
    ilha_pj_mais boolean,
    import_batch_id bigint NOT NULL,
    maior_faturamento numeric(18,2),
    melhor_conversa_raw text,
    motivo_entrada_vip character varying,
    net_mdr numeric(12,4),
    net_mdr_status character varying,
    nome_contato_1 character varying,
    nome_contato_2 character varying,
    nome_fantasia character varying,
    parcela_pre_aprovada numeric(18,2),
    possui_link_pgto boolean,
    prazo_pre_aprovado integer,
    qtde_demais_pos integer,
    qtde_mps integer,
    qtde_outros_terminais integer,
    qtde_pin integer,
    qtde_smart_pos integer,
    qtde_tap_on_phone integer,
    qtde_tef integer,
    qtde_total_terminais integer,
    ramo_atividade character varying,
    razao_social character varying,
    segmento_performado character varying,
    segmento_presumido character varying,
    solucoes_financeiras character varying,
    status_antecip_auto_boarding character varying,
    status_antecip_auto_boarding_2 character varying,
    status_contrato character varying,
    status_reciprocidade character varying,
    sub_channel_id bigint NOT NULL,
    taxa_pre_aprovada numeric(12,4),
    telefone_trabalho character varying,
    tipo_pessoa character varying,
    ultimo_acesso_app timestamp(6) without time zone,
    updated_at timestamp(6) without time zone NOT NULL,
    vip_boarding_date timestamp(6) without time zone,
    volume_pre_aprovado numeric(18,2)
);


--
-- Name: revenue_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.revenue_snapshots (
    id bigint NOT NULL,
    ativo_ultimos_60_dias boolean,
    cep character varying,
    cep_raw character varying,
    channel_id bigint NOT NULL,
    cidade character varying,
    cnae_codigo character varying,
    cnae_descricao character varying,
    created_at timestamp(6) without time zone NOT NULL,
    data_suspensao date,
    data_ult_transacao date,
    endereco character varying,
    establishment_id bigint NOT NULL,
    estado character varying,
    fat_total_m1 numeric(18,2) DEFAULT 0.0 NOT NULL,
    fat_total_mes_atual numeric(18,2) DEFAULT 0.0 NOT NULL,
    hierarquia_origem character varying,
    import_batch_id bigint NOT NULL,
    nome_fantasia character varying,
    razao_social character varying,
    status_contrato character varying,
    sub_channel_id bigint NOT NULL,
    telefone_raw character varying,
    telefone_trabalho character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_company_ec_divergence; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.audit_company_ec_divergence AS
 SELECT rs.channel_id,
    e.company_id,
    count(DISTINCT rs.status_contrato) AS status_contrato_distintos,
    count(DISTINCT ms.segmento_performado) AS segmento_performado_distintos
   FROM ((public.revenue_snapshots rs
     JOIN public.establishments e ON ((e.id = rs.establishment_id)))
     LEFT JOIN public.map_snapshots ms ON (((ms.import_batch_id = rs.import_batch_id) AND (ms.establishment_id = rs.establishment_id))))
  GROUP BY rs.channel_id, e.company_id
 HAVING ((count(DISTINCT rs.status_contrato) > 1) OR (count(DISTINCT ms.segmento_performado) > 1))
  WITH NO DATA;


--
-- Name: conversation_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversation_actions (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    texto character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: map_snapshot_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.map_snapshot_actions (
    id bigint NOT NULL,
    conversation_action_id bigint NOT NULL,
    map_snapshot_id bigint NOT NULL,
    posicao integer NOT NULL
);


--
-- Name: audit_pending_actions; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.audit_pending_actions AS
 SELECT ms.channel_id,
    ms.sub_channel_id,
    e.company_id,
    ca.texto,
    count(*) AS total
   FROM (((public.map_snapshot_actions msa
     JOIN public.map_snapshots ms ON ((ms.id = msa.map_snapshot_id)))
     JOIN public.establishments e ON ((e.id = ms.establishment_id)))
     JOIN public.conversation_actions ca ON ((ca.id = msa.conversation_action_id)))
  GROUP BY ms.channel_id, ms.sub_channel_id, e.company_id, ca.texto
  WITH NO DATA;


--
-- Name: competencia_coverages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.competencia_coverages (
    channel_id bigint NOT NULL,
    competencia date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    fechado boolean DEFAULT false NOT NULL,
    max_dia_conhecido integer NOT NULL,
    ultimo_import_batch_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: daily_revenues_consolidated; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_revenues_consolidated (
    amount numeric(18,2) NOT NULL,
    channel_id bigint NOT NULL,
    competencia date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    day integer NOT NULL,
    establishment_id bigint NOT NULL,
    provisional boolean NOT NULL,
    revised_count integer DEFAULT 0 NOT NULL,
    source_import_batch_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: import_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_batches (
    id bigint NOT NULL,
    channel_id bigint NOT NULL,
    competencia_atual date,
    competencia_m1 date,
    competencias_cobertas jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    dia_corte_mes_atual integer,
    file_checksum character varying NOT NULL,
    import_template_id bigint NOT NULL,
    source_file_date date,
    source_filename character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    validation_errors jsonb DEFAULT '[]'::jsonb NOT NULL,
    CONSTRAINT import_batches_valid_cutoff CHECK (((dia_corte_mes_atual >= 1) AND (dia_corte_mes_atual <= 31))),
    CONSTRAINT import_batches_valid_status CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('validated'::character varying)::text, ('failed'::character varying)::text, ('superseded'::character varying)::text])))
);


--
-- Name: sub_channels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sub_channels (
    id bigint NOT NULL,
    channel_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    sub_canal character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: audit_revenue_by_sub_channel; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.audit_revenue_by_sub_channel AS
 WITH periods AS (
         SELECT competencia_coverages.channel_id,
            competencia_coverages.competencia AS competencia_atual,
            competencia_coverages.max_dia_conhecido,
            ((competencia_coverages.competencia - '1 mon'::interval))::date AS competencia_m1
           FROM public.competencia_coverages
          WHERE (NOT competencia_coverages.fechado)
        )
 SELECT rs.channel_id,
    rs.sub_channel_id,
    sc.sub_canal,
    periods.competencia_m1,
    periods.competencia_atual,
    periods.max_dia_conhecido,
    COALESCE(sum(dr.amount) FILTER (WHERE (dr.competencia = periods.competencia_m1)), (0)::numeric) AS faturamento_m1,
    COALESCE(sum(dr.amount) FILTER (WHERE (dr.competencia = periods.competencia_atual)), (0)::numeric) AS faturamento_atual,
    count(DISTINCT rs.establishment_id) FILTER (WHERE (e.primary_establishment_id IS NULL)) AS estabelecimentos_principais
   FROM ((((public.revenue_snapshots rs
     JOIN public.sub_channels sc ON ((sc.id = rs.sub_channel_id)))
     JOIN public.establishments e ON ((e.id = rs.establishment_id)))
     JOIN periods ON ((periods.channel_id = rs.channel_id)))
     LEFT JOIN public.daily_revenues_consolidated dr ON (((dr.channel_id = rs.channel_id) AND (dr.establishment_id = rs.establishment_id) AND ((dr.competencia = periods.competencia_m1) OR (dr.competencia = periods.competencia_atual)) AND (dr.day <= periods.max_dia_conhecido))))
  WHERE (rs.import_batch_id = ( SELECT max(ib.id) AS max
           FROM public.import_batches ib
          WHERE ((ib.channel_id = rs.channel_id) AND ((ib.status)::text = 'validated'::text) AND (EXISTS ( SELECT 1
                   FROM public.revenue_snapshots latest
                  WHERE (latest.import_batch_id = ib.id))))))
  GROUP BY rs.channel_id, rs.sub_channel_id, sc.sub_canal, periods.competencia_m1, periods.competencia_atual, periods.max_dia_conhecido
  WITH NO DATA;


--
-- Name: companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.companies (
    id bigint NOT NULL,
    cnpj character varying(14) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    CONSTRAINT companies_cnpj_format CHECK (((cnpj)::text ~ '^[0-9]{14}$'::text))
);


--
-- Name: audit_revenue_by_company; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.audit_revenue_by_company AS
 SELECT sub_channel.channel_id,
    sub_channel.sub_channel_id,
    e.company_id,
    c.cnpj,
    sub_channel.max_dia_conhecido,
    sub_channel.competencia_m1,
    sub_channel.competencia_atual,
    COALESCE(sum(dr.amount) FILTER (WHERE (dr.competencia = sub_channel.competencia_m1)), (0)::numeric) AS faturamento_m1,
    COALESCE(sum(dr.amount) FILTER (WHERE (dr.competencia = sub_channel.competencia_atual)), (0)::numeric) AS faturamento_atual
   FROM ((((public.audit_revenue_by_sub_channel sub_channel
     JOIN public.revenue_snapshots rs ON (((rs.channel_id = sub_channel.channel_id) AND (rs.sub_channel_id = sub_channel.sub_channel_id))))
     JOIN public.establishments e ON ((e.id = rs.establishment_id)))
     JOIN public.companies c ON ((c.id = e.company_id)))
     LEFT JOIN public.daily_revenues_consolidated dr ON (((dr.channel_id = sub_channel.channel_id) AND (dr.establishment_id = rs.establishment_id) AND ((dr.competencia = sub_channel.competencia_m1) OR (dr.competencia = sub_channel.competencia_atual)) AND (dr.day <= sub_channel.max_dia_conhecido))))
  WHERE (rs.import_batch_id = ( SELECT max(ib.id) AS max
           FROM public.import_batches ib
          WHERE ((ib.channel_id = sub_channel.channel_id) AND ((ib.status)::text = 'validated'::text) AND (EXISTS ( SELECT 1
                   FROM public.revenue_snapshots latest
                  WHERE (latest.import_batch_id = ib.id))))))
  GROUP BY sub_channel.channel_id, sub_channel.sub_channel_id, e.company_id, c.cnpj, sub_channel.max_dia_conhecido, sub_channel.competencia_m1, sub_channel.competencia_atual
  WITH NO DATA;


--
-- Name: audit_stalled_companies; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.audit_stalled_companies AS
 WITH current_activity AS (
         SELECT company_view_1.channel_id,
            company_view_1.sub_channel_id,
            company_view_1.company_id,
            max(dr.day) AS last_sale_day
           FROM ((public.audit_revenue_by_company company_view_1
             JOIN public.establishments e ON (((e.company_id = company_view_1.company_id) AND (e.channel_id = company_view_1.channel_id))))
             JOIN public.daily_revenues_consolidated dr ON (((dr.establishment_id = e.id) AND (dr.channel_id = company_view_1.channel_id) AND (dr.competencia = company_view_1.competencia_atual) AND (dr.day <= company_view_1.max_dia_conhecido))))
          GROUP BY company_view_1.channel_id, company_view_1.sub_channel_id, company_view_1.company_id
        )
 SELECT company_view.channel_id,
    company_view.sub_channel_id,
    sc.sub_canal,
    company_view.company_id,
    company_view.cnpj,
    company_view.max_dia_conhecido,
    activity.last_sale_day,
    (company_view.max_dia_conhecido - activity.last_sale_day) AS dias_sem_venda,
    company_view.faturamento_m1,
    company_view.faturamento_atual
   FROM ((public.audit_revenue_by_company company_view
     JOIN current_activity activity ON (((activity.channel_id = company_view.channel_id) AND (activity.sub_channel_id = company_view.sub_channel_id) AND (activity.company_id = company_view.company_id))))
     JOIN public.sub_channels sc ON ((sc.id = company_view.sub_channel_id)))
  WHERE ((company_view.max_dia_conhecido - activity.last_sale_day) >= 7)
  WITH NO DATA;


--
-- Name: audit_weekly_revenue; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.audit_weekly_revenue AS
 SELECT channel_id,
    competencia,
    (((day - 1) / 7) + 1) AS semana,
    sum(amount) AS faturamento,
    count(DISTINCT establishment_id) AS estabelecimentos
   FROM public.daily_revenues_consolidated
  GROUP BY channel_id, competencia, (((day - 1) / 7) + 1)
  WITH NO DATA;


--
-- Name: channels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channels (
    id bigint NOT NULL,
    canal character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    external_id character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: channels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.channels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.channels_id_seq OWNED BY public.channels.id;


--
-- Name: companies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.companies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: companies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.companies_id_seq OWNED BY public.companies.id;


--
-- Name: conversation_actions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.conversation_actions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: conversation_actions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.conversation_actions_id_seq OWNED BY public.conversation_actions.id;


--
-- Name: daily_revenue_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_revenue_revisions (
    id bigint NOT NULL,
    amount_anterior numeric(18,2) NOT NULL,
    amount_novo numeric(18,2) NOT NULL,
    competencia date NOT NULL,
    day integer NOT NULL,
    detected_at timestamp(6) without time zone NOT NULL,
    establishment_id bigint NOT NULL,
    import_batch_id bigint NOT NULL
);


--
-- Name: daily_revenue_revisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.daily_revenue_revisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: daily_revenue_revisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.daily_revenue_revisions_id_seq OWNED BY public.daily_revenue_revisions.id;


--
-- Name: daily_revenues; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_revenues (
    id bigint NOT NULL,
    import_batch_id bigint NOT NULL,
    channel_id bigint NOT NULL,
    establishment_id bigint NOT NULL,
    competencia date NOT NULL,
    day integer NOT NULL,
    amount numeric(18,2) NOT NULL,
    provisional boolean NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT daily_revenues_valid_day CHECK (((day >= 1) AND (day <= 31)))
)
PARTITION BY RANGE (competencia);


--
-- Name: daily_revenues_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.daily_revenues_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: daily_revenues_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.daily_revenues_id_seq OWNED BY public.daily_revenues.id;


--
-- Name: daily_revenues_202607; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_revenues_202607 (
    id bigint DEFAULT nextval('public.daily_revenues_id_seq'::regclass) NOT NULL,
    import_batch_id bigint NOT NULL,
    channel_id bigint NOT NULL,
    establishment_id bigint NOT NULL,
    competencia date NOT NULL,
    day integer NOT NULL,
    amount numeric(18,2) NOT NULL,
    provisional boolean NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT daily_revenues_valid_day CHECK (((day >= 1) AND (day <= 31)))
);


--
-- Name: daily_revenues_202608; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_revenues_202608 (
    id bigint DEFAULT nextval('public.daily_revenues_id_seq'::regclass) NOT NULL,
    import_batch_id bigint NOT NULL,
    channel_id bigint NOT NULL,
    establishment_id bigint NOT NULL,
    competencia date NOT NULL,
    day integer NOT NULL,
    amount numeric(18,2) NOT NULL,
    provisional boolean NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT daily_revenues_valid_day CHECK (((day >= 1) AND (day <= 31)))
);


--
-- Name: daily_revenues_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_revenues_default (
    id bigint DEFAULT nextval('public.daily_revenues_id_seq'::regclass) NOT NULL,
    import_batch_id bigint NOT NULL,
    channel_id bigint NOT NULL,
    establishment_id bigint NOT NULL,
    competencia date NOT NULL,
    day integer NOT NULL,
    amount numeric(18,2) NOT NULL,
    provisional boolean NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT daily_revenues_valid_day CHECK (((day >= 1) AND (day <= 31)))
);


--
-- Name: data_anomalies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_anomalies (
    id bigint NOT NULL,
    anomaly_type character varying NOT NULL,
    channel_id bigint NOT NULL,
    company_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    establishment_id bigint,
    first_detected_at timestamp(6) without time zone NOT NULL,
    first_import_batch_id bigint NOT NULL,
    last_detected_at timestamp(6) without time zone NOT NULL,
    last_import_batch_id bigint NOT NULL,
    occurrences integer DEFAULT 1 NOT NULL,
    resolution_note text,
    resolved_at timestamp(6) without time zone,
    resolved_by character varying,
    severity character varying NOT NULL,
    status character varying DEFAULT 'aberta'::character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: data_anomalies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.data_anomalies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: data_anomalies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.data_anomalies_id_seq OWNED BY public.data_anomalies.id;


--
-- Name: establishments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.establishments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: establishments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.establishments_id_seq OWNED BY public.establishments.id;


--
-- Name: import_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.import_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_batches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.import_batches_id_seq OWNED BY public.import_batches.id;


--
-- Name: import_template_columns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_template_columns (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    import_template_id bigint NOT NULL,
    normalization_rule character varying,
    required boolean DEFAULT false NOT NULL,
    sheet_name character varying NOT NULL,
    source_header character varying NOT NULL,
    target_field character varying,
    target_table character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: import_template_columns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.import_template_columns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_template_columns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.import_template_columns_id_seq OWNED BY public.import_template_columns.id;


--
-- Name: import_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_templates (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL,
    sheet_names jsonb DEFAULT '[]'::jsonb NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: import_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.import_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.import_templates_id_seq OWNED BY public.import_templates.id;


--
-- Name: map_snapshot_actions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.map_snapshot_actions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: map_snapshot_actions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.map_snapshot_actions_id_seq OWNED BY public.map_snapshot_actions.id;


--
-- Name: map_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.map_snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: map_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.map_snapshots_id_seq OWNED BY public.map_snapshots.id;


--
-- Name: monthly_volumes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.monthly_volumes (
    id bigint NOT NULL,
    amount numeric(18,2) NOT NULL,
    channel_id bigint NOT NULL,
    competencia date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    establishment_id bigint NOT NULL,
    import_batch_id bigint NOT NULL,
    metrica character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: monthly_volumes_consolidated; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.monthly_volumes_consolidated (
    amount numeric(18,2) NOT NULL,
    channel_id bigint NOT NULL,
    competencia date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    establishment_id bigint NOT NULL,
    metrica character varying NOT NULL,
    source_import_batch_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: monthly_volumes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.monthly_volumes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: monthly_volumes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.monthly_volumes_id_seq OWNED BY public.monthly_volumes.id;


--
-- Name: raw_import_rows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.raw_import_rows (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    import_batch_id bigint NOT NULL,
    payload jsonb NOT NULL,
    row_number integer NOT NULL,
    sheet_name character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: raw_import_rows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.raw_import_rows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: raw_import_rows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.raw_import_rows_id_seq OWNED BY public.raw_import_rows.id;


--
-- Name: revenue_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.revenue_snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: revenue_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.revenue_snapshots_id_seq OWNED BY public.revenue_snapshots.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: solid_queue_blocked_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_blocked_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    concurrency_key character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_blocked_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_blocked_executions_id_seq OWNED BY public.solid_queue_blocked_executions.id;


--
-- Name: solid_queue_claimed_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_claimed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    process_id bigint,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_claimed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_claimed_executions_id_seq OWNED BY public.solid_queue_claimed_executions.id;


--
-- Name: solid_queue_failed_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_failed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    error text,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_failed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_failed_executions_id_seq OWNED BY public.solid_queue_failed_executions.id;


--
-- Name: solid_queue_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_jobs (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    class_name character varying NOT NULL,
    arguments text,
    priority integer DEFAULT 0 NOT NULL,
    active_job_id character varying,
    scheduled_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    concurrency_key character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_jobs_id_seq OWNED BY public.solid_queue_jobs.id;


--
-- Name: solid_queue_pauses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_pauses (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_pauses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_pauses_id_seq OWNED BY public.solid_queue_pauses.id;


--
-- Name: solid_queue_processes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_processes (
    id bigint NOT NULL,
    kind character varying NOT NULL,
    last_heartbeat_at timestamp(6) without time zone NOT NULL,
    supervisor_id bigint,
    pid integer NOT NULL,
    hostname character varying,
    metadata text,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL
);


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_processes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_processes_id_seq OWNED BY public.solid_queue_processes.id;


--
-- Name: solid_queue_ready_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_ready_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_ready_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_ready_executions_id_seq OWNED BY public.solid_queue_ready_executions.id;


--
-- Name: solid_queue_recurring_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_recurring_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    task_key character varying NOT NULL,
    run_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_recurring_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_recurring_executions_id_seq OWNED BY public.solid_queue_recurring_executions.id;


--
-- Name: solid_queue_recurring_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_recurring_tasks (
    id bigint NOT NULL,
    key character varying NOT NULL,
    schedule character varying NOT NULL,
    command character varying(2048),
    class_name character varying,
    arguments text,
    queue_name character varying,
    priority integer DEFAULT 0,
    static boolean DEFAULT true NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_recurring_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_recurring_tasks_id_seq OWNED BY public.solid_queue_recurring_tasks.id;


--
-- Name: solid_queue_scheduled_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_scheduled_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    scheduled_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_scheduled_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_scheduled_executions_id_seq OWNED BY public.solid_queue_scheduled_executions.id;


--
-- Name: solid_queue_semaphores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_semaphores (
    id bigint NOT NULL,
    key character varying NOT NULL,
    value integer DEFAULT 1 NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_semaphores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_semaphores_id_seq OWNED BY public.solid_queue_semaphores.id;


--
-- Name: sub_channels_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sub_channels_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sub_channels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sub_channels_id_seq OWNED BY public.sub_channels.id;


--
-- Name: daily_revenues_202607; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_revenues ATTACH PARTITION public.daily_revenues_202607 FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');


--
-- Name: daily_revenues_202608; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_revenues ATTACH PARTITION public.daily_revenues_202608 FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');


--
-- Name: daily_revenues_default; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_revenues ATTACH PARTITION public.daily_revenues_default DEFAULT;


--
-- Name: activation_proposals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_proposals ALTER COLUMN id SET DEFAULT nextval('public.activation_proposals_id_seq'::regclass);


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: channels id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channels ALTER COLUMN id SET DEFAULT nextval('public.channels_id_seq'::regclass);


--
-- Name: companies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies ALTER COLUMN id SET DEFAULT nextval('public.companies_id_seq'::regclass);


--
-- Name: conversation_actions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_actions ALTER COLUMN id SET DEFAULT nextval('public.conversation_actions_id_seq'::regclass);


--
-- Name: daily_revenue_revisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_revenue_revisions ALTER COLUMN id SET DEFAULT nextval('public.daily_revenue_revisions_id_seq'::regclass);


--
-- Name: daily_revenues id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_revenues ALTER COLUMN id SET DEFAULT nextval('public.daily_revenues_id_seq'::regclass);


--
-- Name: data_anomalies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_anomalies ALTER COLUMN id SET DEFAULT nextval('public.data_anomalies_id_seq'::regclass);


--
-- Name: establishments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.establishments ALTER COLUMN id SET DEFAULT nextval('public.establishments_id_seq'::regclass);


--
-- Name: import_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_batches ALTER COLUMN id SET DEFAULT nextval('public.import_batches_id_seq'::regclass);


--
-- Name: import_template_columns id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_template_columns ALTER COLUMN id SET DEFAULT nextval('public.import_template_columns_id_seq'::regclass);


--
-- Name: import_templates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_templates ALTER COLUMN id SET DEFAULT nextval('public.import_templates_id_seq'::regclass);


--
-- Name: map_snapshot_actions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_snapshot_actions ALTER COLUMN id SET DEFAULT nextval('public.map_snapshot_actions_id_seq'::regclass);


--
-- Name: map_snapshots id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_snapshots ALTER COLUMN id SET DEFAULT nextval('public.map_snapshots_id_seq'::regclass);


--
-- Name: monthly_volumes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monthly_volumes ALTER COLUMN id SET DEFAULT nextval('public.monthly_volumes_id_seq'::regclass);


--
-- Name: raw_import_rows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.raw_import_rows ALTER COLUMN id SET DEFAULT nextval('public.raw_import_rows_id_seq'::regclass);


--
-- Name: revenue_snapshots id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revenue_snapshots ALTER COLUMN id SET DEFAULT nextval('public.revenue_snapshots_id_seq'::regclass);


--
-- Name: solid_queue_blocked_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_blocked_executions_id_seq'::regclass);


--
-- Name: solid_queue_claimed_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_claimed_executions_id_seq'::regclass);


--
-- Name: solid_queue_failed_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_failed_executions_id_seq'::regclass);


--
-- Name: solid_queue_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_jobs ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_jobs_id_seq'::regclass);


--
-- Name: solid_queue_pauses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_pauses ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_pauses_id_seq'::regclass);


--
-- Name: solid_queue_processes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_processes ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_processes_id_seq'::regclass);


--
-- Name: solid_queue_ready_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_ready_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_recurring_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_tasks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_tasks ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_recurring_tasks_id_seq'::regclass);


--
-- Name: solid_queue_scheduled_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_scheduled_executions_id_seq'::regclass);


--
-- Name: solid_queue_semaphores id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_semaphores ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_semaphores_id_seq'::regclass);


--
-- Name: sub_channels id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_channels ALTER COLUMN id SET DEFAULT nextval('public.sub_channels_id_seq'::regclass);


--
-- Name: activation_proposals activation_proposals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_proposals
    ADD CONSTRAINT activation_proposals_pkey PRIMARY KEY (id);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: channels channels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channels
    ADD CONSTRAINT channels_pkey PRIMARY KEY (id);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: conversation_actions conversation_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_actions
    ADD CONSTRAINT conversation_actions_pkey PRIMARY KEY (id);


--
-- Name: daily_revenue_revisions daily_revenue_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_revenue_revisions
    ADD CONSTRAINT daily_revenue_revisions_pkey PRIMARY KEY (id);


--
-- Name: data_anomalies data_anomalies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_anomalies
    ADD CONSTRAINT data_anomalies_pkey PRIMARY KEY (id);


--
-- Name: establishments establishments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.establishments
    ADD CONSTRAINT establishments_pkey PRIMARY KEY (id);


--
-- Name: import_batches import_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT import_batches_pkey PRIMARY KEY (id);


--
-- Name: import_template_columns import_template_columns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_template_columns
    ADD CONSTRAINT import_template_columns_pkey PRIMARY KEY (id);


--
-- Name: import_templates import_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_templates
    ADD CONSTRAINT import_templates_pkey PRIMARY KEY (id);


--
-- Name: map_snapshot_actions map_snapshot_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_snapshot_actions
    ADD CONSTRAINT map_snapshot_actions_pkey PRIMARY KEY (id);


--
-- Name: map_snapshots map_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_snapshots
    ADD CONSTRAINT map_snapshots_pkey PRIMARY KEY (id);


--
-- Name: monthly_volumes monthly_volumes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monthly_volumes
    ADD CONSTRAINT monthly_volumes_pkey PRIMARY KEY (id);


--
-- Name: raw_import_rows raw_import_rows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.raw_import_rows
    ADD CONSTRAINT raw_import_rows_pkey PRIMARY KEY (id);


--
-- Name: revenue_snapshots revenue_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revenue_snapshots
    ADD CONSTRAINT revenue_snapshots_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: solid_queue_blocked_executions solid_queue_blocked_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions
    ADD CONSTRAINT solid_queue_blocked_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_claimed_executions solid_queue_claimed_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT solid_queue_claimed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_failed_executions solid_queue_failed_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT solid_queue_failed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_jobs solid_queue_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_jobs
    ADD CONSTRAINT solid_queue_jobs_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_pauses solid_queue_pauses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_pauses
    ADD CONSTRAINT solid_queue_pauses_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_processes solid_queue_processes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_processes
    ADD CONSTRAINT solid_queue_processes_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_ready_executions solid_queue_ready_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT solid_queue_ready_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_executions solid_queue_recurring_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT solid_queue_recurring_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_tasks solid_queue_recurring_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_tasks
    ADD CONSTRAINT solid_queue_recurring_tasks_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_scheduled_executions solid_queue_scheduled_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT solid_queue_scheduled_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_semaphores solid_queue_semaphores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_semaphores
    ADD CONSTRAINT solid_queue_semaphores_pkey PRIMARY KEY (id);


--
-- Name: sub_channels sub_channels_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_channels
    ADD CONSTRAINT sub_channels_pkey PRIMARY KEY (id);


--
-- Name: index_daily_revenues_on_channel_id_and_competencia_and_day; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_revenues_on_channel_id_and_competencia_and_day ON ONLY public.daily_revenues USING btree (channel_id, competencia, day);


--
-- Name: daily_revenues_202607_channel_id_competencia_day_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_202607_channel_id_competencia_day_idx ON public.daily_revenues_202607 USING btree (channel_id, competencia, day);


--
-- Name: index_daily_revenues_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_revenues_on_channel_id ON ONLY public.daily_revenues USING btree (channel_id);


--
-- Name: daily_revenues_202607_channel_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_202607_channel_id_idx ON public.daily_revenues_202607 USING btree (channel_id);


--
-- Name: index_daily_revenues_on_establishment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_revenues_on_establishment_id ON ONLY public.daily_revenues USING btree (establishment_id);


--
-- Name: daily_revenues_202607_establishment_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_202607_establishment_id_idx ON public.daily_revenues_202607 USING btree (establishment_id);


--
-- Name: index_daily_revenues_unique_snapshot_day; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_daily_revenues_unique_snapshot_day ON ONLY public.daily_revenues USING btree (import_batch_id, establishment_id, competencia, day);


--
-- Name: daily_revenues_202607_import_batch_id_establishment_id_comp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX daily_revenues_202607_import_batch_id_establishment_id_comp_idx ON public.daily_revenues_202607 USING btree (import_batch_id, establishment_id, competencia, day);


--
-- Name: index_daily_revenues_on_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_revenues_on_import_batch_id ON ONLY public.daily_revenues USING btree (import_batch_id);


--
-- Name: daily_revenues_202607_import_batch_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_202607_import_batch_id_idx ON public.daily_revenues_202607 USING btree (import_batch_id);


--
-- Name: daily_revenues_202608_channel_id_competencia_day_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_202608_channel_id_competencia_day_idx ON public.daily_revenues_202608 USING btree (channel_id, competencia, day);


--
-- Name: daily_revenues_202608_channel_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_202608_channel_id_idx ON public.daily_revenues_202608 USING btree (channel_id);


--
-- Name: daily_revenues_202608_establishment_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_202608_establishment_id_idx ON public.daily_revenues_202608 USING btree (establishment_id);


--
-- Name: daily_revenues_202608_import_batch_id_establishment_id_comp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX daily_revenues_202608_import_batch_id_establishment_id_comp_idx ON public.daily_revenues_202608 USING btree (import_batch_id, establishment_id, competencia, day);


--
-- Name: daily_revenues_202608_import_batch_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_202608_import_batch_id_idx ON public.daily_revenues_202608 USING btree (import_batch_id);


--
-- Name: daily_revenues_default_channel_id_competencia_day_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_default_channel_id_competencia_day_idx ON public.daily_revenues_default USING btree (channel_id, competencia, day);


--
-- Name: daily_revenues_default_channel_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_default_channel_id_idx ON public.daily_revenues_default USING btree (channel_id);


--
-- Name: daily_revenues_default_establishment_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_default_establishment_id_idx ON public.daily_revenues_default USING btree (establishment_id);


--
-- Name: daily_revenues_default_import_batch_id_establishment_id_com_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX daily_revenues_default_import_batch_id_establishment_id_com_idx ON public.daily_revenues_default USING btree (import_batch_id, establishment_id, competencia, day);


--
-- Name: daily_revenues_default_import_batch_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_default_import_batch_id_idx ON public.daily_revenues_default USING btree (import_batch_id);


--
-- Name: idx_on_channel_id_competencia_1e171e2307; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_channel_id_competencia_1e171e2307 ON public.monthly_volumes_consolidated USING btree (channel_id, competencia);


--
-- Name: idx_on_channel_id_competencia_day_d976e5a0fc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_channel_id_competencia_day_d976e5a0fc ON public.daily_revenues_consolidated USING btree (channel_id, competencia, day);


--
-- Name: idx_on_import_batch_id_establishment_id_1c09c84b4a; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_import_batch_id_establishment_id_1c09c84b4a ON public.revenue_snapshots USING btree (import_batch_id, establishment_id);


--
-- Name: idx_on_import_batch_id_nr_da_proposta_532af95e97; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_import_batch_id_nr_da_proposta_532af95e97 ON public.activation_proposals USING btree (import_batch_id, nr_da_proposta);


--
-- Name: index_activation_proposals_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activation_proposals_on_channel_id ON public.activation_proposals USING btree (channel_id);


--
-- Name: index_activation_proposals_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activation_proposals_on_company_id ON public.activation_proposals USING btree (company_id);


--
-- Name: index_activation_proposals_on_establishment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activation_proposals_on_establishment_id ON public.activation_proposals USING btree (establishment_id);


--
-- Name: index_activation_proposals_on_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activation_proposals_on_import_batch_id ON public.activation_proposals USING btree (import_batch_id);


--
-- Name: index_activation_proposals_on_nr_da_proposta; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activation_proposals_on_nr_da_proposta ON public.activation_proposals USING btree (nr_da_proposta);


--
-- Name: index_activation_proposals_on_sub_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activation_proposals_on_sub_channel_id ON public.activation_proposals USING btree (sub_channel_id);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_audit_company_ec_divergence; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_company_ec_divergence ON public.audit_company_ec_divergence USING btree (channel_id, company_id);


--
-- Name: index_audit_pending_actions; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_pending_actions ON public.audit_pending_actions USING btree (channel_id, sub_channel_id, company_id, texto);


--
-- Name: index_audit_revenue_by_company; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_revenue_by_company ON public.audit_revenue_by_company USING btree (channel_id, sub_channel_id, company_id);


--
-- Name: index_audit_revenue_by_sub_channel; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_revenue_by_sub_channel ON public.audit_revenue_by_sub_channel USING btree (channel_id, sub_channel_id);


--
-- Name: index_audit_stalled_companies; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_stalled_companies ON public.audit_stalled_companies USING btree (channel_id, sub_channel_id, company_id);


--
-- Name: index_audit_weekly_revenue; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_weekly_revenue ON public.audit_weekly_revenue USING btree (channel_id, competencia, semana);


--
-- Name: index_channels_on_canal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channels_on_canal ON public.channels USING gin (canal public.gin_trgm_ops);


--
-- Name: index_channels_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_channels_on_external_id ON public.channels USING btree (external_id);


--
-- Name: index_channels_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_channels_on_uuid ON public.channels USING btree (uuid);


--
-- Name: index_companies_on_cnpj; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_companies_on_cnpj ON public.companies USING btree (cnpj);


--
-- Name: index_companies_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_companies_on_uuid ON public.companies USING btree (uuid);


--
-- Name: index_competencia_coverages_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_competencia_coverages_on_channel_id ON public.competencia_coverages USING btree (channel_id);


--
-- Name: index_competencia_coverages_on_channel_id_and_competencia; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_competencia_coverages_on_channel_id_and_competencia ON public.competencia_coverages USING btree (channel_id, competencia);


--
-- Name: index_competencia_coverages_on_ultimo_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_competencia_coverages_on_ultimo_import_batch_id ON public.competencia_coverages USING btree (ultimo_import_batch_id);


--
-- Name: index_conversation_actions_on_texto; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_conversation_actions_on_texto ON public.conversation_actions USING btree (texto);


--
-- Name: index_daily_revenue_revisions_on_establishment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_revenue_revisions_on_establishment_id ON public.daily_revenue_revisions USING btree (establishment_id);


--
-- Name: index_daily_revenue_revisions_on_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_revenue_revisions_on_import_batch_id ON public.daily_revenue_revisions USING btree (import_batch_id);


--
-- Name: index_daily_revenues_consolidated_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_revenues_consolidated_on_channel_id ON public.daily_revenues_consolidated USING btree (channel_id);


--
-- Name: index_daily_revenues_consolidated_on_establishment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_revenues_consolidated_on_establishment_id ON public.daily_revenues_consolidated USING btree (establishment_id);


--
-- Name: index_daily_revenues_consolidated_on_source_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_revenues_consolidated_on_source_import_batch_id ON public.daily_revenues_consolidated USING btree (source_import_batch_id);


--
-- Name: index_daily_revenues_consolidated_primary; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_daily_revenues_consolidated_primary ON public.daily_revenues_consolidated USING btree (establishment_id, competencia, day);


--
-- Name: index_data_anomalies_deduplication; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_data_anomalies_deduplication ON public.data_anomalies USING btree (channel_id, anomaly_type, company_id, establishment_id);


--
-- Name: index_data_anomalies_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_anomalies_on_channel_id ON public.data_anomalies USING btree (channel_id);


--
-- Name: index_data_anomalies_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_anomalies_on_company_id ON public.data_anomalies USING btree (company_id);


--
-- Name: index_data_anomalies_on_establishment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_anomalies_on_establishment_id ON public.data_anomalies USING btree (establishment_id);


--
-- Name: index_data_anomalies_on_first_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_anomalies_on_first_import_batch_id ON public.data_anomalies USING btree (first_import_batch_id);


--
-- Name: index_data_anomalies_on_last_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_data_anomalies_on_last_import_batch_id ON public.data_anomalies USING btree (last_import_batch_id);


--
-- Name: index_data_anomalies_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_data_anomalies_on_uuid ON public.data_anomalies USING btree (uuid);


--
-- Name: index_establishments_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_establishments_on_channel_id ON public.establishments USING btree (channel_id);


--
-- Name: index_establishments_on_channel_id_and_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_establishments_on_channel_id_and_company_id ON public.establishments USING btree (channel_id, company_id);


--
-- Name: index_establishments_on_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_establishments_on_company_id ON public.establishments USING btree (company_id);


--
-- Name: index_establishments_on_ec; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_establishments_on_ec ON public.establishments USING btree (ec);


--
-- Name: index_establishments_on_primary_establishment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_establishments_on_primary_establishment_id ON public.establishments USING btree (primary_establishment_id);


--
-- Name: index_establishments_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_establishments_on_uuid ON public.establishments USING btree (uuid);


--
-- Name: index_import_batches_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_batches_on_channel_id ON public.import_batches USING btree (channel_id);


--
-- Name: index_import_batches_on_channel_id_and_competencia_atual; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_batches_on_channel_id_and_competencia_atual ON public.import_batches USING btree (channel_id, competencia_atual);


--
-- Name: index_import_batches_on_file_checksum; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_import_batches_on_file_checksum ON public.import_batches USING btree (file_checksum);


--
-- Name: index_import_batches_on_import_template_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_batches_on_import_template_id ON public.import_batches USING btree (import_template_id);


--
-- Name: index_import_batches_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_import_batches_on_uuid ON public.import_batches USING btree (uuid);


--
-- Name: index_import_template_columns_on_import_template_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_template_columns_on_import_template_id ON public.import_template_columns USING btree (import_template_id);


--
-- Name: index_import_templates_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_import_templates_on_name ON public.import_templates USING btree (name);


--
-- Name: index_map_snapshot_actions_on_conversation_action_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_snapshot_actions_on_conversation_action_id ON public.map_snapshot_actions USING btree (conversation_action_id);


--
-- Name: index_map_snapshot_actions_on_map_snapshot_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_snapshot_actions_on_map_snapshot_id ON public.map_snapshot_actions USING btree (map_snapshot_id);


--
-- Name: index_map_snapshot_actions_unique_action; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_map_snapshot_actions_unique_action ON public.map_snapshot_actions USING btree (map_snapshot_id, conversation_action_id);


--
-- Name: index_map_snapshots_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_snapshots_on_channel_id ON public.map_snapshots USING btree (channel_id);


--
-- Name: index_map_snapshots_on_channel_id_and_sub_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_snapshots_on_channel_id_and_sub_channel_id ON public.map_snapshots USING btree (channel_id, sub_channel_id);


--
-- Name: index_map_snapshots_on_cidade; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_snapshots_on_cidade ON public.map_snapshots USING gin (cidade public.gin_trgm_ops);


--
-- Name: index_map_snapshots_on_establishment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_snapshots_on_establishment_id ON public.map_snapshots USING btree (establishment_id);


--
-- Name: index_map_snapshots_on_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_snapshots_on_import_batch_id ON public.map_snapshots USING btree (import_batch_id);


--
-- Name: index_map_snapshots_on_import_batch_id_and_establishment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_map_snapshots_on_import_batch_id_and_establishment_id ON public.map_snapshots USING btree (import_batch_id, establishment_id);


--
-- Name: index_map_snapshots_on_nome_fantasia; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_snapshots_on_nome_fantasia ON public.map_snapshots USING gin (nome_fantasia public.gin_trgm_ops);


--
-- Name: index_map_snapshots_on_razao_social; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_snapshots_on_razao_social ON public.map_snapshots USING gin (razao_social public.gin_trgm_ops);


--
-- Name: index_map_snapshots_on_sub_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_snapshots_on_sub_channel_id ON public.map_snapshots USING btree (sub_channel_id);


--
-- Name: index_monthly_volumes_consolidated_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monthly_volumes_consolidated_on_channel_id ON public.monthly_volumes_consolidated USING btree (channel_id);


--
-- Name: index_monthly_volumes_consolidated_on_establishment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monthly_volumes_consolidated_on_establishment_id ON public.monthly_volumes_consolidated USING btree (establishment_id);


--
-- Name: index_monthly_volumes_consolidated_on_source_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monthly_volumes_consolidated_on_source_import_batch_id ON public.monthly_volumes_consolidated USING btree (source_import_batch_id);


--
-- Name: index_monthly_volumes_consolidated_primary; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_monthly_volumes_consolidated_primary ON public.monthly_volumes_consolidated USING btree (establishment_id, competencia, metrica);


--
-- Name: index_monthly_volumes_on_batch_establishment_competencia_metric; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_monthly_volumes_on_batch_establishment_competencia_metric ON public.monthly_volumes USING btree (import_batch_id, establishment_id, competencia, metrica);


--
-- Name: index_monthly_volumes_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monthly_volumes_on_channel_id ON public.monthly_volumes USING btree (channel_id);


--
-- Name: index_monthly_volumes_on_channel_id_and_competencia; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monthly_volumes_on_channel_id_and_competencia ON public.monthly_volumes USING btree (channel_id, competencia);


--
-- Name: index_monthly_volumes_on_establishment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monthly_volumes_on_establishment_id ON public.monthly_volumes USING btree (establishment_id);


--
-- Name: index_monthly_volumes_on_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monthly_volumes_on_import_batch_id ON public.monthly_volumes USING btree (import_batch_id);


--
-- Name: index_raw_import_rows_on_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_raw_import_rows_on_import_batch_id ON public.raw_import_rows USING btree (import_batch_id);


--
-- Name: index_raw_import_rows_unique_source_row; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_raw_import_rows_unique_source_row ON public.raw_import_rows USING btree (import_batch_id, sheet_name, row_number);


--
-- Name: index_revenue_snapshots_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_revenue_snapshots_on_channel_id ON public.revenue_snapshots USING btree (channel_id);


--
-- Name: index_revenue_snapshots_on_channel_id_and_sub_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_revenue_snapshots_on_channel_id_and_sub_channel_id ON public.revenue_snapshots USING btree (channel_id, sub_channel_id);


--
-- Name: index_revenue_snapshots_on_establishment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_revenue_snapshots_on_establishment_id ON public.revenue_snapshots USING btree (establishment_id);


--
-- Name: index_revenue_snapshots_on_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_revenue_snapshots_on_import_batch_id ON public.revenue_snapshots USING btree (import_batch_id);


--
-- Name: index_revenue_snapshots_on_sub_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_revenue_snapshots_on_sub_channel_id ON public.revenue_snapshots USING btree (sub_channel_id);


--
-- Name: index_solid_queue_blocked_executions_for_maintenance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_maintenance ON public.solid_queue_blocked_executions USING btree (expires_at, concurrency_key);


--
-- Name: index_solid_queue_blocked_executions_for_release; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_release ON public.solid_queue_blocked_executions USING btree (concurrency_key, priority, job_id);


--
-- Name: index_solid_queue_blocked_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_blocked_executions_on_job_id ON public.solid_queue_blocked_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_claimed_executions_on_job_id ON public.solid_queue_claimed_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_process_id_and_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_claimed_executions_on_process_id_and_job_id ON public.solid_queue_claimed_executions USING btree (process_id, job_id);


--
-- Name: index_solid_queue_dispatch_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_dispatch_all ON public.solid_queue_scheduled_executions USING btree (scheduled_at, priority, job_id);


--
-- Name: index_solid_queue_failed_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_failed_executions_on_job_id ON public.solid_queue_failed_executions USING btree (job_id);


--
-- Name: index_solid_queue_jobs_for_alerting; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_alerting ON public.solid_queue_jobs USING btree (scheduled_at, finished_at);


--
-- Name: index_solid_queue_jobs_for_filtering; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_filtering ON public.solid_queue_jobs USING btree (queue_name, finished_at);


--
-- Name: index_solid_queue_jobs_on_active_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_active_job_id ON public.solid_queue_jobs USING btree (active_job_id);


--
-- Name: index_solid_queue_jobs_on_class_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_class_name ON public.solid_queue_jobs USING btree (class_name);


--
-- Name: index_solid_queue_jobs_on_finished_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_finished_at ON public.solid_queue_jobs USING btree (finished_at);


--
-- Name: index_solid_queue_pauses_on_queue_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_pauses_on_queue_name ON public.solid_queue_pauses USING btree (queue_name);


--
-- Name: index_solid_queue_poll_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_poll_all ON public.solid_queue_ready_executions USING btree (priority, job_id);


--
-- Name: index_solid_queue_poll_by_queue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_poll_by_queue ON public.solid_queue_ready_executions USING btree (queue_name, priority, job_id);


--
-- Name: index_solid_queue_processes_on_last_heartbeat_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_last_heartbeat_at ON public.solid_queue_processes USING btree (last_heartbeat_at);


--
-- Name: index_solid_queue_processes_on_name_and_supervisor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_processes_on_name_and_supervisor_id ON public.solid_queue_processes USING btree (name, supervisor_id);


--
-- Name: index_solid_queue_processes_on_supervisor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_supervisor_id ON public.solid_queue_processes USING btree (supervisor_id);


--
-- Name: index_solid_queue_ready_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_ready_executions_on_job_id ON public.solid_queue_ready_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_job_id ON public.solid_queue_recurring_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_task_key_and_run_at; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_task_key_and_run_at ON public.solid_queue_recurring_executions USING btree (task_key, run_at);


--
-- Name: index_solid_queue_recurring_tasks_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_tasks_on_key ON public.solid_queue_recurring_tasks USING btree (key);


--
-- Name: index_solid_queue_recurring_tasks_on_static; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_recurring_tasks_on_static ON public.solid_queue_recurring_tasks USING btree (static);


--
-- Name: index_solid_queue_scheduled_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_scheduled_executions_on_job_id ON public.solid_queue_scheduled_executions USING btree (job_id);


--
-- Name: index_solid_queue_semaphores_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_expires_at ON public.solid_queue_semaphores USING btree (expires_at);


--
-- Name: index_solid_queue_semaphores_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_semaphores_on_key ON public.solid_queue_semaphores USING btree (key);


--
-- Name: index_solid_queue_semaphores_on_key_and_value; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_key_and_value ON public.solid_queue_semaphores USING btree (key, value);


--
-- Name: index_sub_channels_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sub_channels_on_channel_id ON public.sub_channels USING btree (channel_id);


--
-- Name: index_sub_channels_on_channel_id_and_sub_canal; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sub_channels_on_channel_id_and_sub_canal ON public.sub_channels USING btree (channel_id, sub_canal);


--
-- Name: index_sub_channels_on_sub_canal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sub_channels_on_sub_canal ON public.sub_channels USING gin (sub_canal public.gin_trgm_ops);


--
-- Name: index_sub_channels_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sub_channels_on_uuid ON public.sub_channels USING btree (uuid);


--
-- Name: index_template_columns_on_template_sheet_header; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_template_columns_on_template_sheet_header ON public.import_template_columns USING btree (import_template_id, sheet_name, source_header);


--
-- Name: daily_revenues_202607_channel_id_competencia_day_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_channel_id_and_competencia_and_day ATTACH PARTITION public.daily_revenues_202607_channel_id_competencia_day_idx;


--
-- Name: daily_revenues_202607_channel_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_channel_id ATTACH PARTITION public.daily_revenues_202607_channel_id_idx;


--
-- Name: daily_revenues_202607_establishment_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_establishment_id ATTACH PARTITION public.daily_revenues_202607_establishment_id_idx;


--
-- Name: daily_revenues_202607_import_batch_id_establishment_id_comp_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_unique_snapshot_day ATTACH PARTITION public.daily_revenues_202607_import_batch_id_establishment_id_comp_idx;


--
-- Name: daily_revenues_202607_import_batch_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_import_batch_id ATTACH PARTITION public.daily_revenues_202607_import_batch_id_idx;


--
-- Name: daily_revenues_202608_channel_id_competencia_day_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_channel_id_and_competencia_and_day ATTACH PARTITION public.daily_revenues_202608_channel_id_competencia_day_idx;


--
-- Name: daily_revenues_202608_channel_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_channel_id ATTACH PARTITION public.daily_revenues_202608_channel_id_idx;


--
-- Name: daily_revenues_202608_establishment_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_establishment_id ATTACH PARTITION public.daily_revenues_202608_establishment_id_idx;


--
-- Name: daily_revenues_202608_import_batch_id_establishment_id_comp_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_unique_snapshot_day ATTACH PARTITION public.daily_revenues_202608_import_batch_id_establishment_id_comp_idx;


--
-- Name: daily_revenues_202608_import_batch_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_import_batch_id ATTACH PARTITION public.daily_revenues_202608_import_batch_id_idx;


--
-- Name: daily_revenues_default_channel_id_competencia_day_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_channel_id_and_competencia_and_day ATTACH PARTITION public.daily_revenues_default_channel_id_competencia_day_idx;


--
-- Name: daily_revenues_default_channel_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_channel_id ATTACH PARTITION public.daily_revenues_default_channel_id_idx;


--
-- Name: daily_revenues_default_establishment_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_establishment_id ATTACH PARTITION public.daily_revenues_default_establishment_id_idx;


--
-- Name: daily_revenues_default_import_batch_id_establishment_id_com_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_unique_snapshot_day ATTACH PARTITION public.daily_revenues_default_import_batch_id_establishment_id_com_idx;


--
-- Name: daily_revenues_default_import_batch_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_import_batch_id ATTACH PARTITION public.daily_revenues_default_import_batch_id_idx;


--
-- Name: daily_revenues daily_revenues_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.daily_revenues
    ADD CONSTRAINT daily_revenues_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: daily_revenues daily_revenues_establishment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.daily_revenues
    ADD CONSTRAINT daily_revenues_establishment_id_fkey FOREIGN KEY (establishment_id) REFERENCES public.establishments(id);


--
-- Name: daily_revenues daily_revenues_import_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.daily_revenues
    ADD CONSTRAINT daily_revenues_import_batch_id_fkey FOREIGN KEY (import_batch_id) REFERENCES public.import_batches(id);


--
-- Name: competencia_coverages fk_rails_000bcb485e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.competencia_coverages
    ADD CONSTRAINT fk_rails_000bcb485e FOREIGN KEY (ultimo_import_batch_id) REFERENCES public.import_batches(id);


--
-- Name: establishments fk_rails_100dc39262; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.establishments
    ADD CONSTRAINT fk_rails_100dc39262 FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: establishments fk_rails_1751fcc373; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.establishments
    ADD CONSTRAINT fk_rails_1751fcc373 FOREIGN KEY (primary_establishment_id) REFERENCES public.establishments(id);


--
-- Name: monthly_volumes fk_rails_17bb3c2ed5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monthly_volumes
    ADD CONSTRAINT fk_rails_17bb3c2ed5 FOREIGN KEY (establishment_id) REFERENCES public.establishments(id);


--
-- Name: sub_channels fk_rails_182414d4ff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_channels
    ADD CONSTRAINT fk_rails_182414d4ff FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: map_snapshots fk_rails_1cbc25a136; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_snapshots
    ADD CONSTRAINT fk_rails_1cbc25a136 FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: raw_import_rows fk_rails_23e94a8d22; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.raw_import_rows
    ADD CONSTRAINT fk_rails_23e94a8d22 FOREIGN KEY (import_batch_id) REFERENCES public.import_batches(id);


--
-- Name: map_snapshot_actions fk_rails_2ba5ea8fd2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_snapshot_actions
    ADD CONSTRAINT fk_rails_2ba5ea8fd2 FOREIGN KEY (conversation_action_id) REFERENCES public.conversation_actions(id);


--
-- Name: import_batches fk_rails_2d1abab0ab; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT fk_rails_2d1abab0ab FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: solid_queue_recurring_executions fk_rails_318a5533ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT fk_rails_318a5533ed FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: activation_proposals fk_rails_34fe6c1be8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_proposals
    ADD CONSTRAINT fk_rails_34fe6c1be8 FOREIGN KEY (import_batch_id) REFERENCES public.import_batches(id);


--
-- Name: solid_queue_failed_executions fk_rails_39bbc7a631; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT fk_rails_39bbc7a631 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: daily_revenues_consolidated fk_rails_3d75727979; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_revenues_consolidated
    ADD CONSTRAINT fk_rails_3d75727979 FOREIGN KEY (source_import_batch_id) REFERENCES public.import_batches(id);


--
-- Name: activation_proposals fk_rails_3e2cf93365; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_proposals
    ADD CONSTRAINT fk_rails_3e2cf93365 FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: map_snapshot_actions fk_rails_41ab25db24; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_snapshot_actions
    ADD CONSTRAINT fk_rails_41ab25db24 FOREIGN KEY (map_snapshot_id) REFERENCES public.map_snapshots(id);


--
-- Name: monthly_volumes_consolidated fk_rails_467b521bd7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monthly_volumes_consolidated
    ADD CONSTRAINT fk_rails_467b521bd7 FOREIGN KEY (source_import_batch_id) REFERENCES public.import_batches(id);


--
-- Name: import_batches fk_rails_48bc178500; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT fk_rails_48bc178500 FOREIGN KEY (import_template_id) REFERENCES public.import_templates(id);


--
-- Name: solid_queue_blocked_executions fk_rails_4cd34e2228; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions
    ADD CONSTRAINT fk_rails_4cd34e2228 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: monthly_volumes fk_rails_4e1cc6e90d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monthly_volumes
    ADD CONSTRAINT fk_rails_4e1cc6e90d FOREIGN KEY (import_batch_id) REFERENCES public.import_batches(id);


--
-- Name: data_anomalies fk_rails_4f62a6a025; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_anomalies
    ADD CONSTRAINT fk_rails_4f62a6a025 FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: competencia_coverages fk_rails_50ae0ba67c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.competencia_coverages
    ADD CONSTRAINT fk_rails_50ae0ba67c FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: data_anomalies fk_rails_5cde571f18; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_anomalies
    ADD CONSTRAINT fk_rails_5cde571f18 FOREIGN KEY (establishment_id) REFERENCES public.establishments(id);


--
-- Name: map_snapshots fk_rails_5fafef3302; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_snapshots
    ADD CONSTRAINT fk_rails_5fafef3302 FOREIGN KEY (import_batch_id) REFERENCES public.import_batches(id);


--
-- Name: activation_proposals fk_rails_668c1a261b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_proposals
    ADD CONSTRAINT fk_rails_668c1a261b FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: daily_revenues_consolidated fk_rails_6d94f1b4d1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_revenues_consolidated
    ADD CONSTRAINT fk_rails_6d94f1b4d1 FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: monthly_volumes fk_rails_6dd23e36a3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monthly_volumes
    ADD CONSTRAINT fk_rails_6dd23e36a3 FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: daily_revenue_revisions fk_rails_727a551ec4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_revenue_revisions
    ADD CONSTRAINT fk_rails_727a551ec4 FOREIGN KEY (import_batch_id) REFERENCES public.import_batches(id);


--
-- Name: data_anomalies fk_rails_7b73fb8956; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_anomalies
    ADD CONSTRAINT fk_rails_7b73fb8956 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: solid_queue_ready_executions fk_rails_81fcbd66af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT fk_rails_81fcbd66af FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: revenue_snapshots fk_rails_841e1d8c40; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revenue_snapshots
    ADD CONSTRAINT fk_rails_841e1d8c40 FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- Name: activation_proposals fk_rails_85a98fe3d3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_proposals
    ADD CONSTRAINT fk_rails_85a98fe3d3 FOREIGN KEY (sub_channel_id) REFERENCES public.sub_channels(id);


--
-- Name: map_snapshots fk_rails_871a8c7db3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_snapshots
    ADD CONSTRAINT fk_rails_871a8c7db3 FOREIGN KEY (establishment_id) REFERENCES public.establishments(id);


--
-- Name: data_anomalies fk_rails_8bb1cb3bc2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_anomalies
    ADD CONSTRAINT fk_rails_8bb1cb3bc2 FOREIGN KEY (first_import_batch_id) REFERENCES public.import_batches(id);


--
-- Name: data_anomalies fk_rails_960274a47a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_anomalies
    ADD CONSTRAINT fk_rails_960274a47a FOREIGN KEY (last_import_batch_id) REFERENCES public.import_batches(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: map_snapshots fk_rails_9b590ad339; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_snapshots
    ADD CONSTRAINT fk_rails_9b590ad339 FOREIGN KEY (sub_channel_id) REFERENCES public.sub_channels(id);


--
-- Name: solid_queue_claimed_executions fk_rails_9cfe4d4944; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT fk_rails_9cfe4d4944 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: monthly_volumes_consolidated fk_rails_a6a3961b76; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monthly_volumes_consolidated
    ADD CONSTRAINT fk_rails_a6a3961b76 FOREIGN KEY (establishment_id) REFERENCES public.establishments(id);


--
-- Name: revenue_snapshots fk_rails_addfa79a4a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revenue_snapshots
    ADD CONSTRAINT fk_rails_addfa79a4a FOREIGN KEY (sub_channel_id) REFERENCES public.sub_channels(id);


--
-- Name: import_template_columns fk_rails_b4e94b48ab; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_template_columns
    ADD CONSTRAINT fk_rails_b4e94b48ab FOREIGN KEY (import_template_id) REFERENCES public.import_templates(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: solid_queue_scheduled_executions fk_rails_c4316f352d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT fk_rails_c4316f352d FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: daily_revenues_consolidated fk_rails_c4413b93fe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_revenues_consolidated
    ADD CONSTRAINT fk_rails_c4413b93fe FOREIGN KEY (establishment_id) REFERENCES public.establishments(id);


--
-- Name: revenue_snapshots fk_rails_c45c8540be; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revenue_snapshots
    ADD CONSTRAINT fk_rails_c45c8540be FOREIGN KEY (import_batch_id) REFERENCES public.import_batches(id);


--
-- Name: activation_proposals fk_rails_c7f690b3ca; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_proposals
    ADD CONSTRAINT fk_rails_c7f690b3ca FOREIGN KEY (establishment_id) REFERENCES public.establishments(id);


--
-- Name: revenue_snapshots fk_rails_dfba7bbb40; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revenue_snapshots
    ADD CONSTRAINT fk_rails_dfba7bbb40 FOREIGN KEY (establishment_id) REFERENCES public.establishments(id);


--
-- Name: establishments fk_rails_dfda61e9e3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.establishments
    ADD CONSTRAINT fk_rails_dfda61e9e3 FOREIGN KEY (company_id) REFERENCES public.companies(id);


--
-- Name: daily_revenue_revisions fk_rails_f294b864d5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_revenue_revisions
    ADD CONSTRAINT fk_rails_f294b864d5 FOREIGN KEY (establishment_id) REFERENCES public.establishments(id);


--
-- Name: monthly_volumes_consolidated fk_rails_f7ad3184cf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monthly_volumes_consolidated
    ADD CONSTRAINT fk_rails_f7ad3184cf FOREIGN KEY (channel_id) REFERENCES public.channels(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260830030000'),
('20260830020000'),
('20260830010000'),
('20260829270000'),
('20260829260000'),
('20260829250000'),
('20260829240000'),
('20260829230000'),
('20260829220000'),
('20260829210000'),
('20260829190000');

