--
-- PostgreSQL database dump
--

\restrict XH1awDdM5TYzz6HagYSoGAq78pfrd7FJLgj19uiDB98DK6jiqpng7wvtTeyyoIF

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
-- Name: action_history; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.action_history (
    action_id integer NOT NULL,
    action text NOT NULL,
    action_date timestamp without time zone,
    action_level text NOT NULL,
    result boolean DEFAULT true NOT NULL,
    submission_id text,
    submitter_id text
);


--
-- Name: action_history_action_id_seq; Type: SEQUENCE; Schema: mass; Owner: -
--

CREATE SEQUENCE mass.action_history_action_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: action_history_action_id_seq; Type: SEQUENCE OWNED BY; Schema: mass; Owner: -
--

ALTER SEQUENCE mass.action_history_action_id_seq OWNED BY mass.action_history.action_id;


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
-- Name: project; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.project (
    submission_id text NOT NULL,
    comment text,
    created_date timestamp without time zone DEFAULT now() NOT NULL,
    dist_date timestamp without time zone,
    issued_date timestamp without time zone,
    modified_date timestamp without time zone DEFAULT now() NOT NULL,
    project_id_counter integer NOT NULL,
    project_id_prefix text DEFAULT 'PRJDB'::text,
    project_type text NOT NULL,
    release_date timestamp without time zone,
    status_id integer
);


--
-- Name: project_project_id_counter_seq; Type: SEQUENCE; Schema: mass; Owner: -
--

CREATE SEQUENCE mass.project_project_id_counter_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: project_project_id_counter_seq; Type: SEQUENCE OWNED BY; Schema: mass; Owner: -
--

ALTER SEQUENCE mass.project_project_id_counter_seq OWNED BY mass.project.project_id_counter;


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
    charge_id integer DEFAULT 1 NOT NULL,
    created_date timestamp without time zone DEFAULT now() NOT NULL,
    form_status_flags character varying(6) DEFAULT '000000'::character varying,
    modified_date timestamp without time zone DEFAULT now() NOT NULL,
    status_id integer DEFAULT 100,
    submitter_id text
);


--
-- Name: submission_data; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.submission_data (
    data_name text NOT NULL,
    data_value text,
    form_name text,
    modified_date timestamp without time zone DEFAULT now() NOT NULL,
    submission_id text NOT NULL,
    t_order integer DEFAULT '-1'::integer NOT NULL
);


--
-- Name: xml; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.xml (
    content text NOT NULL,
    registered_date text DEFAULT now() NOT NULL,
    submission_id text NOT NULL,
    version integer NOT NULL
);


--
-- Name: action_history action_id; Type: DEFAULT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.action_history ALTER COLUMN action_id SET DEFAULT nextval('mass.action_history_action_id_seq'::regclass);


--
-- Name: project project_id_counter; Type: DEFAULT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.project ALTER COLUMN project_id_counter SET DEFAULT nextval('mass.project_project_id_counter_seq'::regclass);


--
-- Name: action_history action_history_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.action_history
    ADD CONSTRAINT action_history_pkey PRIMARY KEY (action_id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: project project_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.project
    ADD CONSTRAINT project_pkey PRIMARY KEY (submission_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: submission_data submission_data_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.submission_data
    ADD CONSTRAINT submission_data_pkey PRIMARY KEY (submission_id, data_name, t_order);


--
-- Name: submission submission_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.submission
    ADD CONSTRAINT submission_pkey PRIMARY KEY (submission_id);


--
-- Name: xml xml_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.xml
    ADD CONSTRAINT xml_pkey PRIMARY KEY (submission_id, version);


--
-- PostgreSQL database dump complete
--

\unrestrict XH1awDdM5TYzz6HagYSoGAq78pfrd7FJLgj19uiDB98DK6jiqpng7wvtTeyyoIF

