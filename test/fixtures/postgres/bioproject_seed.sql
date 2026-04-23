-- bioproject seed: test_valid_bioproject_id? / test_umbrella_project? / test_get_bioproject_accession /
-- test_get_bioproject_submission / test_get_bioproject_names_list / test_get_bioproject_submitter_ids 等

-- submissions 入れ子: submitter_id が必要なものは紐付ける
INSERT INTO mass.submission (submission_id, submitter_id) VALUES
  ('PSUB004141', 'sgibbons'),
  ('PSUB004142', 'anyone'),
  ('PSUB004148', 'anyone'),
  ('PSUB004388', 'anyone'),
  ('PSUB001851', 'anyone'),
  ('PSUB000078', 'anyone'),
  ('PSUB003595', 'anyone'),     -- PRJDB3595 用
  ('PSUB001554', 'anyone'),     -- PRJDB1554 umbrella 用
  ('PSUB001884', 'anyone'),     -- PRJDB1884 (not umbrella)
  ('PSUB001893', 'anyone'),     -- PRJDB1893 umbrella (test_invalid_umbrella_project)
  ('PSUB002342', 'anyone'),     -- PSUB002342 umbrella (test_invalid_umbrella_project submission_id 経由)
  ('PSUB000051', 'anyone'),     -- PRJDB51 (deleted)
  ('PSUB005969', 'anyone'),     -- PRJDB5969
  ('PSUB004841', 'hirakawa'),   -- PRJDB4841
  ('PSUB_ffpri', 'ddbj_ffpri'); -- test_get_bioproject_names_list 用

-- project: submission_id ⇄ project_id_counter マッピング
-- project_type は 'umbrella' / 'primary' (NOT NULL). status_id は 5600/5700 だと除外扱い
-- NOTE: PSUB004148 には project 行を作らない (get_bioproject_accession が nil を返すケースを再現)
INSERT INTO mass.project (submission_id, project_id_prefix, project_id_counter, project_type, status_id) VALUES
  ('PSUB004141', 'PRJDB', 3490, 'primary',  NULL),
  ('PSUB004142', 'PRJDB', 4142, 'primary',  NULL),
  ('PSUB004388', 'PRJDB', 4388, 'primary',  NULL),
  ('PSUB001851', 'PRJDB', 1851, 'umbrella', NULL),
  ('PSUB000078', 'PRJDB',   78, 'primary',  5700),  -- deleted
  ('PSUB003595', 'PRJDB', 3595, 'primary',  NULL),
  ('PSUB001554', 'PRJDB', 1554, 'umbrella', NULL),
  ('PSUB001884', 'PRJDB', 1884, 'primary',  NULL),
  ('PSUB001893', 'PRJDB', 1893, 'umbrella', NULL),
  ('PSUB002342', 'PRJDB', 2342, 'umbrella', NULL),
  ('PSUB000051', 'PRJDB',   51, 'primary',  5700),  -- deleted
  ('PSUB005969', 'PRJDB', 5969, 'primary',  NULL),
  ('PSUB004841', 'PRJDB', 4841, 'primary',  NULL),
  ('PSUB_ffpri', 'PRJDB', 9999, 'primary',  NULL);

-- submission_data: test_get_bioproject_names_list が期待する project_name を投入
INSERT INTO mass.submission_data (submission_id, data_name, data_value) VALUES
  ('PSUB_ffpri', 'project_name', 'Diurnal transcriptome dynamics of Japanese cedar (Cryptomeria japonica) in summer and winter');
