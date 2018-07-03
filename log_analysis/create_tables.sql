DROP TABLE IF EXISTS tbl_annotation cascade;
DROP TABLE IF EXISTS tbl_message cascade;
DROP TABLE IF EXISTS tbl_status cascade;

CREATE TABLE tbl_status (
  uuid varchar(36) PRIMARY KEY,
  api_version varchar(20),
  status varchar(20),
  start_time timestamp,
  end_time timestamp,
  ip_address varchar(20),
  submitter_id varchar(100),
  error_count int,
  warning_count int,
  common_error int,
  common_warning int,
  external_error int,
  external_warning int,
  autocorrect_biosample bool,
  autocorrect_bioproject bool,
  autocorrect_submission bool,
  autocorrect_experiment bool,
  autocorrect_run bool,
  autocorrect_analysis bool,
  bs_submission_id varchar(100),
  bs_num_of_samples int,
  bs_package varchar(200)
);

CREATE TABLE tbl_message (
  uuid varchar(36),
  message_no int,
  rule_id varchar(20),
  level varchar(10),
  external boolean,
  method varchar(100),
  object varchar(100),
  source varchar(255),
  CONSTRAINT msg_pkey primary key (uuid, message_no),
  FOREIGN KEY (uuid) REFERENCES tbl_status (uuid)
);

CREATE TABLE tbl_annotation (
  uuid varchar(36),
  message_no int,
  annotation_no int,
  key varchar(255),
  value varchar(2000),
  suggested_value varchar(2000),
  target_key varchar(255),
  location varchar(2000),
  is_auto_annotation boolean,
  is_suggest boolean,
  CONSTRAINT anno_pkey primary key (uuid, message_no, annotation_no),
  FOREIGN KEY (uuid, message_no) REFERENCES tbl_message (uuid, message_no)
);
