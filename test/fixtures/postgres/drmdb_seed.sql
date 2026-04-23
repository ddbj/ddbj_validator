-- drmdb seed: 外部 ID (PSUB/PRJNA) 参照者テーブル + DRA エンティティ/リレーション + submission group view

-- ================================================================
-- 外部 ID → 参照許可 submitter (test_get_bioproject_referenceable_submitter_ids)
-- ext_entity.status は NOT NULL。validator は WHERE status = 100 で filter するので 100 を入れる
-- ================================================================

INSERT INTO mass.ext_entity (ext_id, acc_type, ref_name, status) VALUES
  -- PSUB004388 → 2 submitters
  (10, 'PSUB',  'PSUB004388', 100),
  -- PRJDB3595 → (bioproject 経由で PSUB003595 になる) → 2 submitters
  (11, 'PSUB',  'PSUB003595', 100),
  -- PRJNA71719 → 1 submitter
  (12, 'PRJNA', 'PRJNA71719', 100);

INSERT INTO mass.ext_permit (per_id, ext_id, submitter_id) VALUES
  (1, 10, 'submitter_a'), (2, 10, 'submitter_b'),
  (3, 11, 'submitter_c'), (4, 11, 'submitter_d'),
  (5, 12, 'submitter_e');

-- ================================================================
-- DRA リンク用 (test_get_bioproject_id_via_dra / test_get_run_id_via_dra /
--               test_get_biosample_related_id / test_exist_check_run_ids / test_get_run_submitter_ids)
--
-- 構造:
--   ext_entity(ref_name='<smp_id>') --ext_relation--> SSUB accession --PSUB ext_entity (BioProject)
--   ext_entity(ref_name='<smp_id>') --ext_relation--> DRX accession --accession_relation--> DRR accession
--   どちらも grp_id を通じて current_dra_submission_group_view に紐づく
-- ================================================================

-- smp_id 64274 (SAMD00052344) → PRJDB4841 / DRR060518 (submitter hirakawa)
-- smp_id 104969               → PRJDB5969
-- validator の get_bioproject_id_via_dra query 1 は ext_entity.acc_type='SSUB' で filter する。
-- 内部的にはこの ext_entity が「SMP (smp_id) を含む SSUB 登録」を表す想定の命名ぽい
INSERT INTO mass.ext_entity (ext_id, acc_type, ref_name, status) VALUES
  (20, 'SSUB', '64274',        100),
  (21, 'PSUB', 'PSUB004841',   100),   -- → PRJDB4841
  (22, 'SSUB', '104969',       100),
  (23, 'PSUB', 'PSUB005969',   100);   -- → PRJDB5969

-- ext_relation: SMP/PSUB と SSUB accession の紐付け
INSERT INTO mass.ext_relation (ext_id, acc_id, grp_id) VALUES
  (20, 'dra_ssub_1',  'grp_prj_1'),   -- SMP 64274 → SSUB
  (21, 'dra_ssub_1',  'grp_prj_1'),   -- PSUB004841 も同じ SSUB に紐付き
  (22, 'dra_ssub_2',  'grp_prj_2'),
  (23, 'dra_ssub_2',  'grp_prj_2'),
  (20, 'dra_drx_1',   'grp_run_1');   -- SMP 64274 → DRX accession (Run 取得用)
-- DRR060519 は smp_id 64274 とは紐付けない
-- (test_get_run_id_via_dra で smp_id 64274 に対して DRR060518 のみ返ることを期待しているため)
-- exist_check_run_ids / get_run_submitter_ids は accession_entity + accession_relation 側だけで
-- 引ける仕組みなのでそちらに独立して存在させる

-- accession_entity (DRX / DRR エンティティ)
-- acc_no は bigint。validator 側で acc_no.rjust(6,'0') されるので数値で入れる
INSERT INTO mass.accession_entity (acc_id, acc_type, acc_no, is_delete) VALUES
  ('dra_drx_1',   'DRX',    1, false),
  ('dra_drr_1',   'DRR',60518, false),
  ('dra_drx_db1', 'DRX',    2, false),
  ('dra_drr_db1', 'DRR',60519, false);

-- accession_relation (DRX -> DRR)
INSERT INTO mass.accession_relation (p_acc_id, acc_id, grp_id) VALUES
  ('dra_drx_1',   'dra_drr_1',   'grp_run_1'),
  ('dra_drx_db1', 'dra_drr_db1', 'grp_run_db1');

-- current_dra_submission_group_view (status NOT IN (900, 1000, 1100) が有効 group)
INSERT INTO mass.current_dra_submission_group_view (grp_id, sub_id, submitter_id, status) VALUES
  ('grp_prj_1',    'sub_prj_1',    'hirakawa', 200),
  ('grp_prj_2',    'sub_prj_2',    'anyone',   200),
  ('grp_run_1',    'sub_run_1',    'hirakawa', 200),
  ('grp_run_db1',  'sub_run_db1',  'someone',  200);
