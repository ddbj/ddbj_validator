--
-- PostgreSQL database dump
--

\restrict c87Hki2TRfg2cfIcJrnYbnV9bLtwW4sU8Opd3FdoTtDpmNIo9Jjdb1ceudsnBt5

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
-- Name: attribute; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.attribute (
    attribute_name text NOT NULL,
    attribute_value text,
    seq_no integer NOT NULL,
    smp_id bigint NOT NULL
);


--
-- Name: contact; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.contact (
    create_date timestamp without time zone DEFAULT now() NOT NULL,
    email text,
    first_name text,
    last_name text,
    modified_date timestamp without time zone DEFAULT now() NOT NULL,
    seq_no integer NOT NULL,
    submission_id text NOT NULL
);


--
-- Name: contact_form; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.contact_form (
    email text,
    first_name text,
    last_name text,
    seq_no integer NOT NULL,
    submission_id text NOT NULL
);


--
-- Name: link; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.link (
    description text,
    seq_no integer NOT NULL,
    smp_id bigint NOT NULL,
    url text
);


--
-- Name: link_form; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.link_form (
    description text,
    seq_no integer NOT NULL,
    submission_id text NOT NULL,
    url text
);


--
-- Name: operation_history; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.operation_history (
    his_id bigint NOT NULL,
    date timestamp without time zone,
    detail bytea,
    file_name text,
    serial integer,
    submission_id text,
    submitter_id text,
    summary text,
    type integer,
    usr_id bigint
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
-- Name: sample; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.sample (
    smp_id bigint NOT NULL,
    core_package integer,
    create_date timestamp without time zone DEFAULT now() NOT NULL,
    dist_date timestamp without time zone,
    env_package text,
    env_pkg integer,
    mixs integer,
    modified_date timestamp without time zone DEFAULT now() NOT NULL,
    package text,
    package_group text,
    pathogen integer,
    release_date timestamp without time zone,
    release_type integer,
    sample_name text NOT NULL,
    status_id integer,
    submission_id text NOT NULL
);


--
-- Name: sample_smp_id_seq; Type: SEQUENCE; Schema: mass; Owner: -
--

CREATE SEQUENCE mass.sample_smp_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sample_smp_id_seq; Type: SEQUENCE OWNED BY; Schema: mass; Owner: -
--

ALTER SEQUENCE mass.sample_smp_id_seq OWNED BY mass.sample.smp_id;


--
-- Name: schema_migrations; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: submission; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.submission (
    submission_id text NOT NULL,
    charge_id integer DEFAULT 1,
    comment text,
    create_date timestamp without time zone DEFAULT now() NOT NULL,
    modified_date timestamp without time zone DEFAULT now() NOT NULL,
    organization text,
    organization_url text,
    submitter_id text
);


--
-- Name: submission_form; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.submission_form (
    submission_id text NOT NULL,
    attribute_file text,
    attribute_file_name text,
    comment text,
    core_package integer,
    create_date timestamp without time zone DEFAULT now() NOT NULL,
    env_package text,
    env_pkg integer,
    mixs integer,
    modified_date timestamp without time zone DEFAULT now() NOT NULL,
    organization text,
    organization_url text,
    package text,
    package_group text,
    pathogen integer,
    release_type integer,
    status_id integer NOT NULL,
    submitter_id text NOT NULL
);


--
-- Name: xml; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.xml (
    accession_id text,
    content text NOT NULL,
    create_date timestamp without time zone DEFAULT now() NOT NULL,
    modified_date timestamp without time zone DEFAULT now() NOT NULL,
    smp_id bigint NOT NULL,
    version integer NOT NULL
);


--
-- Name: operation_history his_id; Type: DEFAULT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.operation_history ALTER COLUMN his_id SET DEFAULT nextval('mass.operation_history_his_id_seq'::regclass);


--
-- Name: sample smp_id; Type: DEFAULT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.sample ALTER COLUMN smp_id SET DEFAULT nextval('mass.sample_smp_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: attribute attribute_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.attribute
    ADD CONSTRAINT attribute_pkey PRIMARY KEY (smp_id, attribute_name);


--
-- Name: contact_form contact_form_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.contact_form
    ADD CONSTRAINT contact_form_pkey PRIMARY KEY (submission_id, seq_no);


--
-- Name: contact contact_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.contact
    ADD CONSTRAINT contact_pkey PRIMARY KEY (submission_id, seq_no);


--
-- Name: link_form link_form_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.link_form
    ADD CONSTRAINT link_form_pkey PRIMARY KEY (submission_id, seq_no);


--
-- Name: link link_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.link
    ADD CONSTRAINT link_pkey PRIMARY KEY (smp_id, seq_no);


--
-- Name: operation_history operation_history_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.operation_history
    ADD CONSTRAINT operation_history_pkey PRIMARY KEY (his_id);


--
-- Name: sample sample_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.sample
    ADD CONSTRAINT sample_pkey PRIMARY KEY (smp_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: submission_form submission_form_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.submission_form
    ADD CONSTRAINT submission_form_pkey PRIMARY KEY (submission_id);


--
-- Name: submission submission_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.submission
    ADD CONSTRAINT submission_pkey PRIMARY KEY (submission_id);


--
-- Name: xml xml_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.xml
    ADD CONSTRAINT xml_pkey PRIMARY KEY (smp_id, version);


--
-- PostgreSQL database dump complete
--

\unrestrict c87Hki2TRfg2cfIcJrnYbnV9bLtwW4sU8Opd3FdoTtDpmNIo9Jjdb1ceudsnBt5

