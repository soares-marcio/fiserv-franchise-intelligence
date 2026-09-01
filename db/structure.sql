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
    import_batch_id bigint NOT NULL,
    channel_id bigint NOT NULL,
    sub_channel_id bigint NOT NULL,
    company_id bigint NOT NULL,
    establishment_id bigint,
    source_hierarchy character varying,
    proposal_number character varying NOT NULL,
    legal_name character varying,
    trade_name character varying,
    proposal_status character varying,
    proposed_on date,
    affiliated_on date,
    installed_on date,
    activated_on date,
    average_ticket numeric(18,2),
    forecast_annual_revenue numeric(18,2),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: COLUMN activation_proposals.source_hierarchy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activation_proposals.source_hierarchy IS 'Origem: coluna "HIERARQUIA" da aba Ativacao';


--
-- Name: COLUMN activation_proposals.proposal_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activation_proposals.proposal_number IS 'Origem: coluna "NR DA PROPOSTA" da aba Ativacao';


--
-- Name: COLUMN activation_proposals.legal_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activation_proposals.legal_name IS 'Origem: coluna "NOME FANTASIA" da aba Ativacao (cabeçalho invertido na origem)';


--
-- Name: COLUMN activation_proposals.trade_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activation_proposals.trade_name IS 'Origem: coluna "RAZÃO SOCIAL" da aba Ativacao (cabeçalho invertido na origem)';


--
-- Name: COLUMN activation_proposals.proposal_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activation_proposals.proposal_status IS 'Origem: coluna "STATUS DA PROPOSTA" da aba Ativacao';


--
-- Name: COLUMN activation_proposals.proposed_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activation_proposals.proposed_on IS 'Origem: coluna "DATA DA PROPOSTA" da aba Ativacao';


--
-- Name: COLUMN activation_proposals.affiliated_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activation_proposals.affiliated_on IS 'Origem: coluna "DATA DE AFILIAÇÃO" da aba Ativacao';


--
-- Name: COLUMN activation_proposals.installed_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activation_proposals.installed_on IS 'Origem: coluna "DATA DE INSTALAÇÃO" da aba Ativacao';


--
-- Name: COLUMN activation_proposals.activated_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activation_proposals.activated_on IS 'Origem: coluna "DATA DE ATIVAÇÃO" da aba Ativacao';


--
-- Name: COLUMN activation_proposals.average_ticket; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activation_proposals.average_ticket IS 'Origem: coluna "TICKET MÉDIO" da aba Ativacao';


--
-- Name: COLUMN activation_proposals.forecast_annual_revenue; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.activation_proposals.forecast_annual_revenue IS 'Origem: coluna "FATURAMENTO ANUAL PREVISTO" da aba Ativacao';


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
-- Name: daily_revenues_consolidated; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_revenues_consolidated (
    establishment_id bigint NOT NULL,
    channel_id bigint NOT NULL,
    period date NOT NULL,
    day integer NOT NULL,
    amount numeric(18,2) NOT NULL,
    provisional boolean NOT NULL,
    source_import_batch_id bigint NOT NULL,
    revised_count integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: import_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_batches (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    channel_id bigint,
    import_template_id bigint,
    source_filename character varying NOT NULL,
    source_file_date date,
    file_checksum character varying NOT NULL,
    previous_period date,
    current_period date,
    covered_periods jsonb DEFAULT '[]'::jsonb NOT NULL,
    current_month_cutoff_day integer,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    validation_errors jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT import_batches_valid_cutoff CHECK (((current_month_cutoff_day >= 1) AND (current_month_cutoff_day <= 31))),
    CONSTRAINT import_batches_valid_status CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('validated'::character varying)::text, ('failed'::character varying)::text, ('superseded'::character varying)::text])))
);


--
-- Name: map_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.map_snapshots (
    id bigint NOT NULL,
    import_batch_id bigint NOT NULL,
    channel_id bigint NOT NULL,
    establishment_id bigint NOT NULL,
    sub_channel_id bigint NOT NULL,
    source_hierarchy character varying,
    entity_type character varying,
    legal_name character varying,
    trade_name character varying,
    business_line character varying,
    cnae_code character varying,
    cnae_description character varying,
    contract_status character varying,
    best_conversation_raw text,
    work_phone character varying,
    street_address character varying,
    cep character varying,
    contact_name_1 character varying,
    contact_name_2 character varying,
    city character varying,
    state character varying,
    pj_mais_island boolean,
    vip_boarding_date timestamp(6) without time zone,
    vip_entry_reason character varying,
    presumed_segment character varying,
    performed_segment character varying,
    reciprocity_status character varying,
    average_revenue_3m numeric(18,2),
    peak_revenue numeric(18,2),
    revenue_diff_m1_m2 numeric(18,2),
    revenue_diff_pct numeric(12,4),
    revenue_drop_cluster character varying,
    active_current_month boolean,
    active_previous_month boolean,
    active_last_30_days boolean,
    last_transaction_on date,
    accredited_on date,
    installed_on date,
    activated_on date,
    suspended_on date,
    last_app_access_at timestamp(6) without time zone,
    financial_solutions character varying,
    auto_advance_boarding_status character varying,
    auto_advance_boarding_status_2 character varying,
    preapproved_volume numeric(18,2),
    preapproved_term integer,
    preapproved_rate numeric(12,4),
    preapproved_installment numeric(18,2),
    has_payment_link boolean,
    tap_on_phone_count integer,
    smart_pos_count integer,
    other_pos_count integer,
    mps_count integer,
    pin_count integer,
    tef_count integer,
    other_terminals_count integer,
    total_terminals_count integer,
    net_mdr numeric(12,4),
    net_mdr_status character varying,
    weekly_schedule character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: COLUMN map_snapshots.source_hierarchy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.source_hierarchy IS 'Origem: coluna "HIERARQUIA" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.entity_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.entity_type IS 'Origem: coluna "TIPO DE PESSOA" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.legal_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.legal_name IS 'Origem: coluna "RAZÃO SOCIAL" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.trade_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.trade_name IS 'Origem: coluna "NOME FANTASIA" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.business_line; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.business_line IS 'Origem: coluna "RAMO DE ATIVIDADE" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.cnae_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.cnae_code IS 'Origem: coluna "CÓDIGO DO CNAE" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.cnae_description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.cnae_description IS 'Origem: coluna "DESCRIÇÃO DO CNAE" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.contract_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.contract_status IS 'Origem: coluna "STATUS DO CONTRATO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.best_conversation_raw; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.best_conversation_raw IS 'Origem: coluna "MELHOR CONVERSA" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.work_phone; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.work_phone IS 'Origem: coluna "TELEFONE DO TRABALHO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.street_address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.street_address IS 'Origem: coluna "ENDEREÇO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.cep; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.cep IS 'Origem: coluna "CEP" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.contact_name_1; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.contact_name_1 IS 'Origem: coluna "NOME CONTATO 1" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.contact_name_2; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.contact_name_2 IS 'Origem: coluna "NOME CONTATO 2" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.city; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.city IS 'Origem: coluna "CIDADE" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.state; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.state IS 'Origem: coluna "ESTADO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.pj_mais_island; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.pj_mais_island IS 'Origem: coluna "Ilha PJ+" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.vip_boarding_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.vip_boarding_date IS 'Origem: coluna "vip_boarding_date" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.vip_entry_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.vip_entry_reason IS 'Origem: coluna "motivo_entrada_vip" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.presumed_segment; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.presumed_segment IS 'Origem: coluna "SEGMENTO PRESUMIDO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.performed_segment; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.performed_segment IS 'Origem: coluna "SEGMENTO PERFORMADO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.reciprocity_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.reciprocity_status IS 'Origem: coluna "STATUS DE RECIPROCIDADE" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.average_revenue_3m; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.average_revenue_3m IS 'Origem: coluna "FATURAMENTO MÉDIO ÚLTIMOS 3 MESES" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.peak_revenue; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.peak_revenue IS 'Origem: coluna "MAIOR FATURAMENTO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.revenue_diff_m1_m2; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.revenue_diff_m1_m2 IS 'Origem: coluna "Diferença Fat M-1 x M-2" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.revenue_diff_pct; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.revenue_diff_pct IS 'Origem: coluna "Diferença Fat %" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.revenue_drop_cluster; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.revenue_drop_cluster IS 'Origem: coluna "Cluster Queda Fat" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.active_current_month; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.active_current_month IS 'Origem: coluna "ATIVO NO MÊS ATUAL?" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.active_previous_month; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.active_previous_month IS 'Origem: coluna "ATIVO NO ULTIMO MÊS?" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.active_last_30_days; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.active_last_30_days IS 'Origem: coluna "ATIVO NOS ÚLTIMOS 30 DIAS?" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.last_transaction_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.last_transaction_on IS 'Origem: coluna "DATA DA ÚLT TRANSAÇÃO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.accredited_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.accredited_on IS 'Origem: coluna "DATA DE CREDENCIAMENTO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.installed_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.installed_on IS 'Origem: coluna "DATA DE INSTALAÇÃO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.activated_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.activated_on IS 'Origem: coluna "DATA DE ATIVAÇÃO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.suspended_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.suspended_on IS 'Origem: coluna "DATA DE SUSPENSÃO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.last_app_access_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.last_app_access_at IS 'Origem: coluna "ULTIMO ACESSO NO APP" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.financial_solutions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.financial_solutions IS 'Origem: coluna "SOLUÇÕES FINANCEIRAS" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.auto_advance_boarding_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.auto_advance_boarding_status IS 'Origem: coluna "STATUS ANTECIP AUTO NO BOARDING" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.auto_advance_boarding_status_2; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.auto_advance_boarding_status_2 IS 'Origem: coluna "STATUS ANTECIP AUTO NO BOARDING.1" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.preapproved_volume; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.preapproved_volume IS 'Origem: coluna "VOLUME_PRE_APROVADO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.preapproved_term; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.preapproved_term IS 'Origem: coluna "PRAZO_PRE_APROVADO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.preapproved_rate; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.preapproved_rate IS 'Origem: coluna "TAXA_PRE_APROVADA" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.preapproved_installment; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.preapproved_installment IS 'Origem: coluna "PARCELA_PRE_APROVADA" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.has_payment_link; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.has_payment_link IS 'Origem: coluna "POSSUI LINK PGTO" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.tap_on_phone_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.tap_on_phone_count IS 'Origem: coluna "QTDE TAP ON PHONE" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.smart_pos_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.smart_pos_count IS 'Origem: coluna "QTDE SMART POS" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.other_pos_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.other_pos_count IS 'Origem: coluna "QTDE DEMAIS POS" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.mps_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.mps_count IS 'Origem: coluna "QTDE MPS" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.pin_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.pin_count IS 'Origem: coluna "QTDE PIN" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.tef_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.tef_count IS 'Origem: coluna "QTDE TEF" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.other_terminals_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.other_terminals_count IS 'Origem: coluna "QTDE OUTROS TERMINAIS" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.total_terminals_count; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.total_terminals_count IS 'Origem: coluna "QTDE TOTAL TERMINAIS" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.net_mdr; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.net_mdr IS 'Origem: coluna "NET MDR" da aba Mapa de Clientes BIN';


--
-- Name: COLUMN map_snapshots.net_mdr_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.net_mdr_status IS 'Origem: coluna "NET MDR" da aba Mapa de Clientes BIN, só quando o valor é "Inativo"';


--
-- Name: COLUMN map_snapshots.weekly_schedule; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshots.weekly_schedule IS 'Origem: coluna "agenda_semanal" da aba Mapa de Clientes BIN';


--
-- Name: period_coverages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.period_coverages (
    channel_id bigint NOT NULL,
    period date NOT NULL,
    max_known_day integer NOT NULL,
    closed boolean DEFAULT false NOT NULL,
    last_import_batch_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_accreditation_earnings; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.audit_accreditation_earnings AS
 WITH latest_map_batches AS (
         SELECT ib.channel_id,
            max(ib.id) AS import_batch_id
           FROM public.import_batches ib
          WHERE (((ib.status)::text = 'validated'::text) AND (EXISTS ( SELECT 1
                   FROM public.map_snapshots m
                  WHERE (m.import_batch_id = ib.id))))
          GROUP BY ib.channel_id
        ), accredited AS (
         SELECT snapshot.channel_id,
            snapshot.sub_channel_id,
            snapshot.establishment_id,
            snapshot.accredited_on,
            (date_trunc('month'::text, (snapshot.accredited_on)::timestamp with time zone))::date AS m0_period,
            (snapshot.last_app_access_at IS NOT NULL) AS has_app_access,
                CASE
                    WHEN ((upper((COALESCE(snapshot.auto_advance_boarding_status, ''::character varying))::text) = ANY (ARRAY['SIM'::text, 'ATIVO'::text, 'TRUE'::text])) OR (upper((COALESCE(snapshot.auto_advance_boarding_status_2, ''::character varying))::text) = ANY (ARRAY['SIM'::text, 'ATIVO'::text, 'TRUE'::text]))) THEN true
                    WHEN ((snapshot.auto_advance_boarding_status IS NOT NULL) OR (snapshot.auto_advance_boarding_status_2 IS NOT NULL)) THEN false
                    ELSE NULL::boolean
                END AS auto_classified
           FROM (public.map_snapshots snapshot
             JOIN latest_map_batches latest ON ((latest.import_batch_id = snapshot.import_batch_id)))
          WHERE (snapshot.accredited_on IS NOT NULL)
        ), month_revenue AS (
         SELECT a.channel_id,
            a.sub_channel_id,
            a.establishment_id,
            a.accredited_on,
            a.m0_period,
            a.has_app_access,
            a.auto_classified,
            months.month_index,
            (cover.channel_id IS NOT NULL) AS month_covered,
            COALESCE(sum(revenue.amount) FILTER (WHERE (cover.closed OR (revenue.day <= cover.max_known_day))), (0)::numeric) AS month_total
           FROM (((accredited a
             CROSS JOIN LATERAL ( VALUES (a.m0_period,0), (((a.m0_period + '1 mon'::interval))::date,1), (((a.m0_period + '2 mons'::interval))::date,2)) months(period, month_index))
             LEFT JOIN public.period_coverages cover ON (((cover.channel_id = a.channel_id) AND (cover.period = months.period))))
             LEFT JOIN public.daily_revenues_consolidated revenue ON (((revenue.channel_id = a.channel_id) AND (revenue.establishment_id = a.establishment_id) AND (revenue.period = months.period))))
          GROUP BY a.channel_id, a.sub_channel_id, a.establishment_id, a.accredited_on, a.m0_period, a.has_app_access, a.auto_classified, months.month_index, cover.channel_id, cover.closed, cover.max_known_day
        )
 SELECT channel_id,
    sub_channel_id,
    establishment_id,
    accredited_on,
    m0_period,
    has_app_access,
    auto_classified,
    count(*) FILTER (WHERE month_covered) AS months_observed,
    max(month_total) FILTER (WHERE month_covered) AS peak_month_revenue,
        CASE
            WHEN (bool_or((month_covered AND (month_index = 0))) AND has_app_access) THEN 30.00
            ELSE (0)::numeric
        END AS digitalization_amount,
        CASE
            WHEN (max(month_total) FILTER (WHERE month_covered) IS NULL) THEN (0)::numeric
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 14999.99) THEN 0.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 19999.99) THEN 50.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 24999.99) THEN 55.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 29999.99) THEN 61.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 34999.99) THEN 67.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 39999.99) THEN 74.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 49999.99) THEN 81.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 59999.99) THEN 89.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 69999.99) THEN 98.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 79999.99) THEN 108.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 89999.99) THEN 119.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 99999.99) THEN 131.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 149999.99) THEN 144.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 199999.99) THEN 158.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 9999999.00) THEN 174.00
            ELSE 174.00
        END AS addon_without_auto,
        CASE
            WHEN (max(month_total) FILTER (WHERE month_covered) IS NULL) THEN (0)::numeric
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 14999.99) THEN 0.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 19999.99) THEN 250.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 24999.99) THEN 300.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 29999.99) THEN 350.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 34999.99) THEN 400.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 39999.99) THEN 450.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 49999.99) THEN 500.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 59999.99) THEN 550.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 69999.99) THEN 690.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 79999.99) THEN 790.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 89999.99) THEN 880.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 99999.99) THEN 950.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 149999.99) THEN 1300.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 199999.99) THEN 1800.00
            WHEN (max(month_total) FILTER (WHERE month_covered) <= 9999999.00) THEN 2200.00
            ELSE 2200.00
        END AS addon_with_auto
   FROM month_revenue
  GROUP BY channel_id, sub_channel_id, establishment_id, accredited_on, m0_period, has_app_access, auto_classified
  WITH NO DATA;


--
-- Name: establishments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.establishments (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    ec character varying(8) NOT NULL,
    company_id bigint NOT NULL,
    channel_id bigint NOT NULL,
    primary_establishment_id bigint,
    duplicate_reason character varying,
    duplicate_confirmed_by character varying,
    duplicate_confirmed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT establishments_ec_format CHECK (((ec)::text ~ '^[0-9]{8}$'::text)),
    CONSTRAINT establishments_not_self_primary CHECK (((primary_establishment_id IS NULL) OR (primary_establishment_id <> id)))
);


--
-- Name: revenue_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.revenue_snapshots (
    id bigint NOT NULL,
    import_batch_id bigint NOT NULL,
    channel_id bigint NOT NULL,
    establishment_id bigint NOT NULL,
    sub_channel_id bigint NOT NULL,
    source_hierarchy character varying,
    legal_name character varying,
    trade_name character varying,
    contract_status character varying,
    suspended_on date,
    last_transaction_on date,
    active_last_60_days boolean,
    street_address character varying,
    cep character varying,
    cep_raw character varying,
    city character varying,
    state character varying,
    work_phone character varying,
    work_phone_raw character varying,
    cnae_code character varying,
    cnae_description character varying,
    previous_month_total numeric(18,2) DEFAULT 0.0 NOT NULL,
    current_month_total numeric(18,2) DEFAULT 0.0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: COLUMN revenue_snapshots.source_hierarchy; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.source_hierarchy IS 'Origem: coluna "HIERARQUIA" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.legal_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.legal_name IS 'Origem: coluna "NOME FANTASIA" da aba Faturamento (cabeçalho invertido na origem)';


--
-- Name: COLUMN revenue_snapshots.trade_name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.trade_name IS 'Origem: coluna "RAZÃO SOCIAL" da aba Faturamento (cabeçalho invertido na origem)';


--
-- Name: COLUMN revenue_snapshots.contract_status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.contract_status IS 'Origem: coluna "STATUS DO CONTRATO" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.suspended_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.suspended_on IS 'Origem: coluna "DATA DE SUSPENSÃO" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.last_transaction_on; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.last_transaction_on IS 'Origem: coluna "DATA DA ÚLT TRANSAÇÃO" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.active_last_60_days; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.active_last_60_days IS 'Origem: coluna "ATIVO NOS ÚLTIMOS 60 DIAS?" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.street_address; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.street_address IS 'Origem: coluna "ENDEREÇO" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.cep; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.cep IS 'Origem: coluna "CEP" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.cep_raw; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.cep_raw IS 'Origem: coluna "CEP" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.city; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.city IS 'Origem: coluna "CIDADE" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.state; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.state IS 'Origem: coluna "ESTADO" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.work_phone; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.work_phone IS 'Origem: coluna "TELEFONE DO TRABALHO" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.work_phone_raw; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.work_phone_raw IS 'Origem: coluna "TELEFONE DO TRABALHO" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.cnae_code; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.cnae_code IS 'Origem: coluna "CNAE" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.cnae_description; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.cnae_description IS 'Origem: coluna "DESCRIÇÃO DO CNAE" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.previous_month_total; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.previous_month_total IS 'Origem: coluna "fat_total_m1" da aba Faturamento';


--
-- Name: COLUMN revenue_snapshots.current_month_total; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.revenue_snapshots.current_month_total IS 'Origem: coluna "FATURAMENTO TOTAL DESTE MÊS" da aba Faturamento';


--
-- Name: audit_company_ec_divergence; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.audit_company_ec_divergence AS
 SELECT rs.channel_id,
    e.company_id,
    count(DISTINCT rs.contract_status) AS distinct_contract_statuses,
    count(DISTINCT ms.performed_segment) AS distinct_performed_segments
   FROM ((public.revenue_snapshots rs
     JOIN public.establishments e ON ((e.id = rs.establishment_id)))
     LEFT JOIN public.map_snapshots ms ON (((ms.import_batch_id = rs.import_batch_id) AND (ms.establishment_id = rs.establishment_id))))
  GROUP BY rs.channel_id, e.company_id
 HAVING ((count(DISTINCT rs.contract_status) > 1) OR (count(DISTINCT ms.performed_segment) > 1))
  WITH NO DATA;


--
-- Name: conversation_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversation_actions (
    id bigint NOT NULL,
    text character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: COLUMN conversation_actions.text; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.conversation_actions.text IS 'Origem: coluna "MELHOR CONVERSA" da aba Mapa de Clientes BIN';


--
-- Name: map_snapshot_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.map_snapshot_actions (
    id bigint NOT NULL,
    map_snapshot_id bigint NOT NULL,
    conversation_action_id bigint NOT NULL,
    "position" integer NOT NULL
);


--
-- Name: COLUMN map_snapshot_actions."position"; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.map_snapshot_actions."position" IS 'Origem: coluna "MELHOR CONVERSA" da aba Mapa de Clientes BIN';


--
-- Name: audit_pending_actions; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.audit_pending_actions AS
 SELECT ms.channel_id,
    ms.sub_channel_id,
    e.company_id,
    ca.text,
    count(*) AS total
   FROM (((public.map_snapshot_actions msa
     JOIN public.map_snapshots ms ON ((ms.id = msa.map_snapshot_id)))
     JOIN public.establishments e ON ((e.id = ms.establishment_id)))
     JOIN public.conversation_actions ca ON ((ca.id = msa.conversation_action_id)))
  GROUP BY ms.channel_id, ms.sub_channel_id, e.company_id, ca.text
  WITH NO DATA;


--
-- Name: sub_channels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sub_channels (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    channel_id bigint NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: COLUMN sub_channels.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.sub_channels.name IS 'Origem: coluna "SUB-CANAL" das abas Mapa de Clientes BIN, Faturamento e Ativacao';


--
-- Name: audit_revenue_by_sub_channel; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.audit_revenue_by_sub_channel AS
 WITH open_cover AS (
         SELECT period_coverages.channel_id,
            period_coverages.period AS current_period,
            period_coverages.max_known_day,
            ((period_coverages.period - '1 mon'::interval))::date AS previous_period
           FROM public.period_coverages
          WHERE ((NOT period_coverages.closed) AND true)
        ), latest_batches AS (
         SELECT ib.channel_id,
            max(ib.id) AS import_batch_id
           FROM public.import_batches ib
          WHERE (((ib.status)::text = 'validated'::text) AND (EXISTS ( SELECT 1
                   FROM public.revenue_snapshots snapshot_1
                  WHERE (snapshot_1.import_batch_id = ib.id))))
          GROUP BY ib.channel_id
        )
 SELECT snapshot.channel_id,
    snapshot.sub_channel_id,
    sub_channel.uuid,
    sub_channel.name AS sub_channel_name,
    cover.previous_period,
    cover.current_period,
    cover.max_known_day,
    COALESCE(sum(revenue.amount) FILTER (WHERE (revenue.period = cover.previous_period)), (0)::numeric) AS previous_full_revenue,
    COALESCE(sum(revenue.amount) FILTER (WHERE ((revenue.period = cover.previous_period) AND (revenue.day <= cover.max_known_day))), (0)::numeric) AS previous_revenue,
    COALESCE(sum(revenue.amount) FILTER (WHERE ((revenue.period = cover.current_period) AND (revenue.day <= cover.max_known_day))), (0)::numeric) AS current_revenue,
    count(DISTINCT snapshot.establishment_id) FILTER (WHERE (establishment.primary_establishment_id IS NULL)) AS primary_establishments
   FROM (((((public.revenue_snapshots snapshot
     JOIN latest_batches latest ON ((latest.import_batch_id = snapshot.import_batch_id)))
     JOIN open_cover cover ON ((cover.channel_id = snapshot.channel_id)))
     JOIN public.sub_channels sub_channel ON ((sub_channel.id = snapshot.sub_channel_id)))
     JOIN public.establishments establishment ON ((establishment.id = snapshot.establishment_id)))
     LEFT JOIN public.daily_revenues_consolidated revenue ON (((revenue.channel_id = snapshot.channel_id) AND (revenue.establishment_id = snapshot.establishment_id) AND ((revenue.period = cover.previous_period) OR (revenue.period = cover.current_period)))))
  GROUP BY snapshot.channel_id, snapshot.sub_channel_id, sub_channel.uuid, sub_channel.name, cover.previous_period, cover.current_period, cover.max_known_day
  WITH NO DATA;


--
-- Name: companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.companies (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    cnpj character varying(14) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT companies_cnpj_format CHECK (((cnpj)::text ~ '^[0-9]{14}$'::text))
);


--
-- Name: audit_revenue_by_company; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.audit_revenue_by_company AS
 SELECT sub_channel.channel_id,
    sub_channel.sub_channel_id,
    establishment.company_id,
    company.cnpj,
    sub_channel.max_known_day,
    sub_channel.previous_period,
    sub_channel.current_period,
    COALESCE(sum(revenue.amount) FILTER (WHERE (revenue.period = sub_channel.previous_period)), (0)::numeric) AS previous_full_revenue,
    COALESCE(sum(revenue.amount) FILTER (WHERE ((revenue.period = sub_channel.previous_period) AND (revenue.day <= sub_channel.max_known_day))), (0)::numeric) AS previous_revenue,
    COALESCE(sum(revenue.amount) FILTER (WHERE ((revenue.period = sub_channel.current_period) AND (revenue.day <= sub_channel.max_known_day))), (0)::numeric) AS current_revenue,
    max(revenue.day) FILTER (WHERE ((revenue.period = sub_channel.current_period) AND (revenue.day <= sub_channel.max_known_day) AND (revenue.amount <> (0)::numeric))) AS last_sale_day
   FROM ((((public.audit_revenue_by_sub_channel sub_channel
     JOIN public.revenue_snapshots snapshot ON (((snapshot.channel_id = sub_channel.channel_id) AND (snapshot.sub_channel_id = sub_channel.sub_channel_id))))
     JOIN public.establishments establishment ON ((establishment.id = snapshot.establishment_id)))
     JOIN public.companies company ON ((company.id = establishment.company_id)))
     LEFT JOIN public.daily_revenues_consolidated revenue ON (((revenue.channel_id = sub_channel.channel_id) AND (revenue.establishment_id = snapshot.establishment_id) AND ((revenue.period = sub_channel.previous_period) OR (revenue.period = sub_channel.current_period)))))
  WHERE (snapshot.import_batch_id = ( SELECT max(ib.id) AS max
           FROM public.import_batches ib
          WHERE ((ib.channel_id = snapshot.channel_id) AND ((ib.status)::text = 'validated'::text) AND (EXISTS ( SELECT 1
                   FROM public.revenue_snapshots latest
                  WHERE (latest.import_batch_id = ib.id))))))
  GROUP BY sub_channel.channel_id, sub_channel.sub_channel_id, establishment.company_id, company.cnpj, sub_channel.max_known_day, sub_channel.previous_period, sub_channel.current_period
  WITH NO DATA;


--
-- Name: audit_stalled_companies; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.audit_stalled_companies AS
 SELECT company_view.channel_id,
    company_view.sub_channel_id,
    sub_channel.name AS sub_channel_name,
    company_view.company_id,
    company_view.cnpj,
    company_view.max_known_day,
    company_view.last_sale_day,
    (company_view.max_known_day - COALESCE(company_view.last_sale_day, 0)) AS days_without_sales,
    company_view.previous_full_revenue,
    company_view.previous_revenue,
    company_view.current_revenue
   FROM (public.audit_revenue_by_company company_view
     JOIN public.sub_channels sub_channel ON ((sub_channel.id = company_view.sub_channel_id)))
  WHERE ((company_view.max_known_day - COALESCE(company_view.last_sale_day, 0)) >= 7)
  WITH NO DATA;


--
-- Name: audit_weekly_revenue; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.audit_weekly_revenue AS
 SELECT channel_id,
    period,
    (((day - 1) / 7) + 1) AS week,
    sum(amount) AS revenue,
    count(DISTINCT establishment_id) AS establishments
   FROM public.daily_revenues_consolidated
  GROUP BY channel_id, period, (((day - 1) / 7) + 1)
  WITH NO DATA;


--
-- Name: channels; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channels (
    id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    external_id character varying NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: COLUMN channels.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.channels.name IS 'Origem: coluna "CANAL" da aba Mapa de Clientes BIN; Faturamento e Ativacao repetem a coluna';


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
    establishment_id bigint NOT NULL,
    period date NOT NULL,
    day integer NOT NULL,
    previous_amount numeric(18,2) NOT NULL,
    new_amount numeric(18,2) NOT NULL,
    import_batch_id bigint NOT NULL,
    detected_at timestamp(6) without time zone NOT NULL
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
    period date NOT NULL,
    day integer NOT NULL,
    amount numeric(18,2) NOT NULL,
    provisional boolean NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT daily_revenues_valid_day CHECK (((day >= 1) AND (day <= 31)))
)
PARTITION BY RANGE (period);


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
-- Name: daily_revenues_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_revenues_default (
    id bigint DEFAULT nextval('public.daily_revenues_id_seq'::regclass) NOT NULL,
    import_batch_id bigint NOT NULL,
    channel_id bigint NOT NULL,
    establishment_id bigint NOT NULL,
    period date NOT NULL,
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
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    channel_id bigint NOT NULL,
    anomaly_type character varying NOT NULL,
    severity character varying NOT NULL,
    company_id bigint,
    establishment_id bigint,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    status character varying DEFAULT 'aberta'::character varying NOT NULL,
    first_detected_at timestamp(6) without time zone NOT NULL,
    last_detected_at timestamp(6) without time zone NOT NULL,
    occurrences integer DEFAULT 1 NOT NULL,
    first_import_batch_id bigint NOT NULL,
    last_import_batch_id bigint NOT NULL,
    resolved_by character varying,
    resolved_at timestamp(6) without time zone,
    resolution_note text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT data_anomalies_valid_severity CHECK (((severity)::text = ANY (ARRAY[('info'::character varying)::text, ('atencao'::character varying)::text, ('erro'::character varying)::text]))),
    CONSTRAINT data_anomalies_valid_status CHECK (((status)::text = ANY (ARRAY[('aberta'::character varying)::text, ('em_analise'::character varying)::text, ('resolvida'::character varying)::text, ('esperada'::character varying)::text])))
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
    import_template_id bigint NOT NULL,
    sheet_name character varying NOT NULL,
    source_header character varying NOT NULL,
    target_table character varying,
    target_field character varying,
    required boolean DEFAULT false NOT NULL,
    normalization_rule character varying,
    created_at timestamp(6) without time zone NOT NULL,
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
    name character varying NOT NULL,
    sheet_names jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
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
    import_batch_id bigint NOT NULL,
    channel_id bigint NOT NULL,
    establishment_id bigint NOT NULL,
    period date NOT NULL,
    metric character varying NOT NULL,
    amount numeric(18,2) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: monthly_volumes_consolidated; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.monthly_volumes_consolidated (
    channel_id bigint NOT NULL,
    establishment_id bigint NOT NULL,
    period date NOT NULL,
    metric character varying NOT NULL,
    amount numeric(18,2) NOT NULL,
    source_import_batch_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
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
    import_batch_id bigint NOT NULL,
    sheet_name character varying NOT NULL,
    row_number integer NOT NULL,
    payload jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
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
-- Name: solid_cable_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_cable_messages (
    id bigint NOT NULL,
    channel bytea NOT NULL,
    payload bytea NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    channel_hash bigint NOT NULL
);


--
-- Name: solid_cable_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_cable_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_cable_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_cable_messages_id_seq OWNED BY public.solid_cable_messages.id;


--
-- Name: solid_cache_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_cache_entries (
    id bigint NOT NULL,
    key bytea NOT NULL,
    value bytea NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    key_hash bigint NOT NULL,
    byte_size integer NOT NULL
);


--
-- Name: solid_cache_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_cache_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_cache_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_cache_entries_id_seq OWNED BY public.solid_cache_entries.id;


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
-- Name: solid_cable_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_cable_messages ALTER COLUMN id SET DEFAULT nextval('public.solid_cable_messages_id_seq'::regclass);


--
-- Name: solid_cache_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_cache_entries ALTER COLUMN id SET DEFAULT nextval('public.solid_cache_entries_id_seq'::regclass);


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
-- Name: solid_cable_messages solid_cable_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_cable_messages
    ADD CONSTRAINT solid_cable_messages_pkey PRIMARY KEY (id);


--
-- Name: solid_cache_entries solid_cache_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_cache_entries
    ADD CONSTRAINT solid_cache_entries_pkey PRIMARY KEY (id);


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
-- Name: index_daily_revenues_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_revenues_on_channel_id ON ONLY public.daily_revenues USING btree (channel_id);


--
-- Name: daily_revenues_default_channel_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_default_channel_id_idx ON public.daily_revenues_default USING btree (channel_id);


--
-- Name: index_daily_revenues_on_channel_id_and_period_and_day; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_revenues_on_channel_id_and_period_and_day ON ONLY public.daily_revenues USING btree (channel_id, period, day);


--
-- Name: daily_revenues_default_channel_id_period_day_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_default_channel_id_period_day_idx ON public.daily_revenues_default USING btree (channel_id, period, day);


--
-- Name: index_daily_revenues_on_establishment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_revenues_on_establishment_id ON ONLY public.daily_revenues USING btree (establishment_id);


--
-- Name: daily_revenues_default_establishment_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_default_establishment_id_idx ON public.daily_revenues_default USING btree (establishment_id);


--
-- Name: index_daily_revenues_unique_snapshot_day; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_daily_revenues_unique_snapshot_day ON ONLY public.daily_revenues USING btree (import_batch_id, establishment_id, period, day);


--
-- Name: daily_revenues_default_import_batch_id_establishment_id_per_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX daily_revenues_default_import_batch_id_establishment_id_per_idx ON public.daily_revenues_default USING btree (import_batch_id, establishment_id, period, day);


--
-- Name: index_daily_revenues_on_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_daily_revenues_on_import_batch_id ON ONLY public.daily_revenues USING btree (import_batch_id);


--
-- Name: daily_revenues_default_import_batch_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX daily_revenues_default_import_batch_id_idx ON public.daily_revenues_default USING btree (import_batch_id);


--
-- Name: idx_on_channel_id_period_day_39f7a9071f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_channel_id_period_day_39f7a9071f ON public.daily_revenues_consolidated USING btree (channel_id, period, day);


--
-- Name: idx_on_import_batch_id_establishment_id_1c09c84b4a; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_import_batch_id_establishment_id_1c09c84b4a ON public.revenue_snapshots USING btree (import_batch_id, establishment_id);


--
-- Name: idx_on_import_batch_id_proposal_number_cee2420935; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_import_batch_id_proposal_number_cee2420935 ON public.activation_proposals USING btree (import_batch_id, proposal_number);


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
-- Name: index_activation_proposals_on_proposal_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activation_proposals_on_proposal_number ON public.activation_proposals USING btree (proposal_number);


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
-- Name: index_audit_accreditation_earnings; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_accreditation_earnings ON public.audit_accreditation_earnings USING btree (channel_id, sub_channel_id, establishment_id);


--
-- Name: index_audit_company_ec_divergence; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_company_ec_divergence ON public.audit_company_ec_divergence USING btree (channel_id, company_id);


--
-- Name: index_audit_pending_actions; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_audit_pending_actions ON public.audit_pending_actions USING btree (channel_id, sub_channel_id, company_id, text);


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

CREATE UNIQUE INDEX index_audit_weekly_revenue ON public.audit_weekly_revenue USING btree (channel_id, period, week);


--
-- Name: index_channels_on_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_channels_on_external_id ON public.channels USING btree (external_id);


--
-- Name: index_channels_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channels_on_name ON public.channels USING gin (name public.gin_trgm_ops);


--
-- Name: index_channels_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_channels_on_uuid ON public.channels USING btree (uuid);


--
-- Name: index_companies_on_cnpj; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_companies_on_cnpj ON public.companies USING btree (cnpj);


--
-- Name: index_companies_on_cnpj_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_companies_on_cnpj_trgm ON public.companies USING gin (cnpj public.gin_trgm_ops);


--
-- Name: index_companies_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_companies_on_uuid ON public.companies USING btree (uuid);


--
-- Name: index_conversation_actions_on_text; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_conversation_actions_on_text ON public.conversation_actions USING btree (text);


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

CREATE UNIQUE INDEX index_daily_revenues_consolidated_primary ON public.daily_revenues_consolidated USING btree (establishment_id, period, day);


--
-- Name: index_data_anomalies_deduplication; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_data_anomalies_deduplication ON public.data_anomalies USING btree (channel_id, anomaly_type, company_id, establishment_id) NULLS NOT DISTINCT;


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
-- Name: index_establishments_on_ec_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_establishments_on_ec_trgm ON public.establishments USING gin (ec public.gin_trgm_ops);


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
-- Name: index_import_batches_on_channel_id_and_current_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_batches_on_channel_id_and_current_period ON public.import_batches USING btree (channel_id, current_period);


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
-- Name: index_map_snapshots_on_city; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_snapshots_on_city ON public.map_snapshots USING gin (city public.gin_trgm_ops);


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
-- Name: index_map_snapshots_on_legal_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_snapshots_on_legal_name ON public.map_snapshots USING gin (legal_name public.gin_trgm_ops);


--
-- Name: index_map_snapshots_on_sub_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_snapshots_on_sub_channel_id ON public.map_snapshots USING btree (sub_channel_id);


--
-- Name: index_map_snapshots_on_trade_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_map_snapshots_on_trade_name ON public.map_snapshots USING gin (trade_name public.gin_trgm_ops);


--
-- Name: index_monthly_volumes_consolidated_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monthly_volumes_consolidated_on_channel_id ON public.monthly_volumes_consolidated USING btree (channel_id);


--
-- Name: index_monthly_volumes_consolidated_on_channel_id_and_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monthly_volumes_consolidated_on_channel_id_and_period ON public.monthly_volumes_consolidated USING btree (channel_id, period);


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

CREATE UNIQUE INDEX index_monthly_volumes_consolidated_primary ON public.monthly_volumes_consolidated USING btree (establishment_id, period, metric);


--
-- Name: index_monthly_volumes_on_batch_establishment_period_metric; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_monthly_volumes_on_batch_establishment_period_metric ON public.monthly_volumes USING btree (import_batch_id, establishment_id, period, metric);


--
-- Name: index_monthly_volumes_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monthly_volumes_on_channel_id ON public.monthly_volumes USING btree (channel_id);


--
-- Name: index_monthly_volumes_on_channel_id_and_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monthly_volumes_on_channel_id_and_period ON public.monthly_volumes USING btree (channel_id, period);


--
-- Name: index_monthly_volumes_on_establishment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monthly_volumes_on_establishment_id ON public.monthly_volumes USING btree (establishment_id);


--
-- Name: index_monthly_volumes_on_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monthly_volumes_on_import_batch_id ON public.monthly_volumes USING btree (import_batch_id);


--
-- Name: index_period_coverages_on_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_period_coverages_on_channel_id ON public.period_coverages USING btree (channel_id);


--
-- Name: index_period_coverages_on_channel_id_and_period; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_period_coverages_on_channel_id_and_period ON public.period_coverages USING btree (channel_id, period);


--
-- Name: index_period_coverages_on_last_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_period_coverages_on_last_import_batch_id ON public.period_coverages USING btree (last_import_batch_id);


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
-- Name: index_revenue_snapshots_on_legal_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_revenue_snapshots_on_legal_name ON public.revenue_snapshots USING gin (legal_name public.gin_trgm_ops);


--
-- Name: index_revenue_snapshots_on_sub_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_revenue_snapshots_on_sub_channel_id ON public.revenue_snapshots USING btree (sub_channel_id);


--
-- Name: index_revenue_snapshots_on_trade_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_revenue_snapshots_on_trade_name ON public.revenue_snapshots USING gin (trade_name public.gin_trgm_ops);


--
-- Name: index_solid_cable_messages_on_channel; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_cable_messages_on_channel ON public.solid_cable_messages USING btree (channel);


--
-- Name: index_solid_cable_messages_on_channel_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_cable_messages_on_channel_hash ON public.solid_cable_messages USING btree (channel_hash);


--
-- Name: index_solid_cable_messages_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_cable_messages_on_created_at ON public.solid_cable_messages USING btree (created_at);


--
-- Name: index_solid_cache_entries_on_byte_size; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_cache_entries_on_byte_size ON public.solid_cache_entries USING btree (byte_size);


--
-- Name: index_solid_cache_entries_on_key_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_cache_entries_on_key_hash ON public.solid_cache_entries USING btree (key_hash);


--
-- Name: index_solid_cache_entries_on_key_hash_and_byte_size; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_cache_entries_on_key_hash_and_byte_size ON public.solid_cache_entries USING btree (key_hash, byte_size);


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
-- Name: index_sub_channels_on_channel_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sub_channels_on_channel_id_and_name ON public.sub_channels USING btree (channel_id, name);


--
-- Name: index_sub_channels_on_id_and_channel_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sub_channels_on_id_and_channel_id ON public.sub_channels USING btree (id, channel_id);


--
-- Name: index_sub_channels_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sub_channels_on_name ON public.sub_channels USING gin (name public.gin_trgm_ops);


--
-- Name: index_sub_channels_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sub_channels_on_uuid ON public.sub_channels USING btree (uuid);


--
-- Name: index_template_columns_on_template_sheet_header; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_template_columns_on_template_sheet_header ON public.import_template_columns USING btree (import_template_id, sheet_name, source_header);


--
-- Name: daily_revenues_default_channel_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_channel_id ATTACH PARTITION public.daily_revenues_default_channel_id_idx;


--
-- Name: daily_revenues_default_channel_id_period_day_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_channel_id_and_period_and_day ATTACH PARTITION public.daily_revenues_default_channel_id_period_day_idx;


--
-- Name: daily_revenues_default_establishment_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_establishment_id ATTACH PARTITION public.daily_revenues_default_establishment_id_idx;


--
-- Name: daily_revenues_default_import_batch_id_establishment_id_per_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_unique_snapshot_day ATTACH PARTITION public.daily_revenues_default_import_batch_id_establishment_id_per_idx;


--
-- Name: daily_revenues_default_import_batch_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_daily_revenues_on_import_batch_id ATTACH PARTITION public.daily_revenues_default_import_batch_id_idx;


--
-- Name: activation_proposals activation_proposals_channel_matches_sub_channel; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activation_proposals
    ADD CONSTRAINT activation_proposals_channel_matches_sub_channel FOREIGN KEY (sub_channel_id, channel_id) REFERENCES public.sub_channels(id, channel_id);


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
-- Name: period_coverages fk_rails_cd45dcdcc3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.period_coverages
    ADD CONSTRAINT fk_rails_cd45dcdcc3 FOREIGN KEY (last_import_batch_id) REFERENCES public.import_batches(id);


--
-- Name: period_coverages fk_rails_d9919fe216; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.period_coverages
    ADD CONSTRAINT fk_rails_d9919fe216 FOREIGN KEY (channel_id) REFERENCES public.channels(id);


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
-- Name: map_snapshots map_snapshots_channel_matches_sub_channel; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.map_snapshots
    ADD CONSTRAINT map_snapshots_channel_matches_sub_channel FOREIGN KEY (sub_channel_id, channel_id) REFERENCES public.sub_channels(id, channel_id);


--
-- Name: revenue_snapshots revenue_snapshots_channel_matches_sub_channel; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revenue_snapshots
    ADD CONSTRAINT revenue_snapshots_channel_matches_sub_channel FOREIGN KEY (sub_channel_id, channel_id) REFERENCES public.sub_channels(id, channel_id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260831120000'),
('20260831010000'),
('20260830070000'),
('20260830060000'),
('20260830050000'),
('20260830040000'),
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

