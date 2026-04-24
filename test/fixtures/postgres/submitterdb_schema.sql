--
-- PostgreSQL database dump
--

\restrict CmP6UuQiCmBbE4rd6Mf0SYztcuVj4akKKaXyNPNxSSyuNFvBpFgXbzqVzERvw4e

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
-- Name: contact; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.contact (
    cnt_id bigint NOT NULL,
    email text,
    first_name text DEFAULT ''::text,
    is_contact boolean DEFAULT false NOT NULL,
    is_pi boolean DEFAULT false NOT NULL,
    last_name text DEFAULT ''::text,
    middle_name text DEFAULT ''::text,
    submitter_id text NOT NULL
);


--
-- Name: contact_cnt_id_seq; Type: SEQUENCE; Schema: mass; Owner: -
--

CREATE SEQUENCE mass.contact_cnt_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: contact_cnt_id_seq; Type: SEQUENCE OWNED BY; Schema: mass; Owner: -
--

ALTER SEQUENCE mass.contact_cnt_id_seq OWNED BY mass.contact.cnt_id;


--
-- Name: login; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.login (
    usr_id bigint NOT NULL,
    create_date timestamp without time zone DEFAULT date_trunc('second'::text, now()),
    need_chgpasswd boolean DEFAULT true,
    password text NOT NULL,
    role integer DEFAULT 0 NOT NULL,
    submitter_id text NOT NULL,
    usable boolean DEFAULT true NOT NULL
);


--
-- Name: login_usr_id_seq; Type: SEQUENCE; Schema: mass; Owner: -
--

CREATE SEQUENCE mass.login_usr_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: login_usr_id_seq; Type: SEQUENCE OWNED BY; Schema: mass; Owner: -
--

ALTER SEQUENCE mass.login_usr_id_seq OWNED BY mass.login.usr_id;


--
-- Name: organization; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.organization (
    submitter_id text NOT NULL,
    address text,
    affiliation text,
    center_name text,
    city text,
    country text,
    department text,
    detail text,
    fax text,
    organization text,
    phone text,
    phone_ext text,
    state text,
    unit text,
    url text,
    zipcode text
);


--
-- Name: schema_migrations; Type: TABLE; Schema: mass; Owner: -
--

CREATE TABLE mass.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: contact cnt_id; Type: DEFAULT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.contact ALTER COLUMN cnt_id SET DEFAULT nextval('mass.contact_cnt_id_seq'::regclass);


--
-- Name: login usr_id; Type: DEFAULT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.login ALTER COLUMN usr_id SET DEFAULT nextval('mass.login_usr_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: contact contact_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.contact
    ADD CONSTRAINT contact_pkey PRIMARY KEY (cnt_id);


--
-- Name: login login_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.login
    ADD CONSTRAINT login_pkey PRIMARY KEY (usr_id);


--
-- Name: organization organization_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.organization
    ADD CONSTRAINT organization_pkey PRIMARY KEY (submitter_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: mass; Owner: -
--

ALTER TABLE ONLY mass.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- PostgreSQL database dump complete
--

\unrestrict CmP6UuQiCmBbE4rd6Mf0SYztcuVj4akKKaXyNPNxSSyuNFvBpFgXbzqVzERvw4e

