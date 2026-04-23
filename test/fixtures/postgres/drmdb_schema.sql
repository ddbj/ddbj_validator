--
-- PostgreSQL database dump
--

\restrict OC0jMQYGf9bX9klq5Dr4S6jK1xn5f8cXwb08CMDIP6UyItp6CIYt9adZSRPfV0C

-- Dumped from database version 18.3
-- Dumped by pg_dump version 18.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: mass; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA mass;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ext_entity; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.ext_entity (
    ext_id bigint NOT NULL,
    acc_type text NOT NULL,
    ref_name text NOT NULL,
    status integer NOT NULL
);


--
-- Name: ext_entity_ext_id_seq; Type: SEQUENCE; Schema: mass; Owner: -
--

CREATE SEQUENCE mass.ext_entity_ext_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ext_entity_ext_id_seq; Type: SEQUENCE OWNED BY; Schema: mass; Owner: -
--

ALTER SEQUENCE mass.ext_entity_ext_id_seq OWNED BY mass.ext_entity.ext_id;


--
-- Name: ext_permit; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.ext_permit (
    per_id bigint NOT NULL,
    ext_id bigint NOT NULL,
    submitter_id text NOT NULL
);


--
-- Name: ext_permit_per_id_seq; Type: SEQUENCE; Schema: mass; Owner: -
--

CREATE SEQUENCE mass.ext_permit_per_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ext_permit_per_id_seq; Type: SEQUENCE OWNED BY; Schema: mass; Owner: -
--

ALTER SEQUENCE mass.ext_permit_per_id_seq OWNED BY mass.ext_permit.per_id;


--
-- Name: operation_history; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.operation_history (
    his_id bigint NOT NULL,
    date timestamp without time zone DEFAULT date_trunc('second'::text, now()) NOT NULL,
    detail bytea,
    file_name text,
    serial integer,
    submitter_id text,
    summary text NOT NULL,
    type integer NOT NULL,
    usr_id bigint NOT NULL
);


--
-- Name: operation_history_his_id_seq; Type: SEQUENCE; Schema: mass; Owner: -
--

CREATE SEQUENCE mass.operation_history_his_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: operation_history_his_id_seq; Type: SEQUENCE OWNED BY; Schema: mass; Owner: -
--

ALTER SEQUENCE mass.operation_history_his_id_seq OWNED BY mass.operation_history.his_id;


--
-- Name: schema_migrations; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: status_history; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.status_history (
    id bigint NOT NULL,
    date timestamp without time zone DEFAULT date_trunc('second'::text, now()) NOT NULL,
    status integer NOT NULL,
    sub_id bigint NOT NULL
);


--
-- Name: status_history_id_seq; Type: SEQUENCE; Schema: mass; Owner: -
--

CREATE SEQUENCE mass.status_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: status_history_id_seq; Type: SEQUENCE OWNED BY; Schema: mass; Owner: -
--

ALTER SEQUENCE mass.status_history_id_seq OWNED BY mass.status_history.id;


--
-- Name: submission; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.submission (
    sub_id bigint NOT NULL,
    charge integer,
    create_date date,
    dist_date date,
    finish_date date,
    hold_date date,
    note text,
    serial integer NOT NULL,
    submit_date date,
    submitter_id text NOT NULL,
    usr_id bigint NOT NULL
);


--
-- Name: submission_sub_id_seq; Type: SEQUENCE; Schema: mass; Owner: -
--

CREATE SEQUENCE mass.submission_sub_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: submission_sub_id_seq; Type: SEQUENCE OWNED BY; Schema: mass; Owner: -
--

ALTER SEQUENCE mass.submission_sub_id_seq OWNED BY mass.submission.sub_id;


--
-- Name: ext_entity ext_id; Type: DEFAULT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.ext_entity ALTER COLUMN ext_id SET DEFAULT nextval('mass.ext_entity_ext_id_seq'::regclass);


--
-- Name: ext_permit per_id; Type: DEFAULT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.ext_permit ALTER COLUMN per_id SET DEFAULT nextval('mass.ext_permit_per_id_seq'::regclass);


--
-- Name: operation_history his_id; Type: DEFAULT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.operation_history ALTER COLUMN his_id SET DEFAULT nextval('mass.operation_history_his_id_seq'::regclass);


--
-- Name: status_history id; Type: DEFAULT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.status_history ALTER COLUMN id SET DEFAULT nextval('mass.status_history_id_seq'::regclass);


--
-- Name: submission sub_id; Type: DEFAULT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.submission ALTER COLUMN sub_id SET DEFAULT nextval('mass.submission_sub_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: ext_entity ext_entity_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.ext_entity
    ADD CONSTRAINT ext_entity_pkey PRIMARY KEY (ext_id);


--
-- Name: ext_permit ext_permit_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.ext_permit
    ADD CONSTRAINT ext_permit_pkey PRIMARY KEY (per_id);


--
-- Name: operation_history operation_history_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.operation_history
    ADD CONSTRAINT operation_history_pkey PRIMARY KEY (his_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: status_history status_history_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.status_history
    ADD CONSTRAINT status_history_pkey PRIMARY KEY (id);


--
-- Name: submission submission_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.submission
    ADD CONSTRAINT submission_pkey PRIMARY KEY (sub_id);


--
-- PostgreSQL database dump complete
--

\unrestrict OC0jMQYGf9bX9klq5Dr4S6jK1xn5f8cXwb08CMDIP6UyItp6CIYt9adZSRPfV0C

