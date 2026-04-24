-- biosample seed: sample / accession / attribute / submission を使うテスト全般
-- (test_get_sample_names, test_is_valid_biosample_id, test_get_biosample_*, test_get_all_locus_tag_prefix 等)

-- submissions
INSERT INTO mass.submission (submission_id, submitter_id) VALUES
  ('SSUB001848', 'hirakawa'),   -- 4 samples
  ('SSUB000020', 'anyone'),     -- SAMD00000007 の親 (locus_tag_prefix=ATW)
  ('SSUB003675', 'anyone'),     -- SAMD00025188 の親
  ('SSUB000001', 'anyone'),     -- 削除済み (status_id=5700)
  ('SSUB000002', 'hirakawa'),   -- SAMD00052344 の親
  ('SSUB000003', 'sokazaki'),   -- SAMD00000001 の親
  ('SSUB000004', 'anyone'),     -- SAMD00023002 の親 (locus_tag 無し)
  ('SSUB000005', 'anyone'),     -- SAMD00060421 の親 (DRA 紐付け無し)
  ('SSUB000006', 'hirotoju'),   -- SAMD00032107-110 の親
  ('SSUB000007', 'anyone'),     -- SAMD00052345 の親
  ('SSUB_LTP',   'anyone'),     -- get_all_locus_tag_prefix 用 (まとめて 200+ サンプル)
  ('SSUB005454', 'anyone'),     -- test_duplicated_locus_tag_prefix: PP14 を登録する submission
  ('SSUB005462', 'anyone'),     -- test_duplicated_locus_tag_prefix: RR1 を登録する別 submission
  ('SSUB_REF',   'anyone');     -- test_get_biosample_info / test_invalid_combination_of_accessions 用

-- samples
-- smp_id は bigint. テストは to_s した値と比較するので、人間が読める値にしておく
INSERT INTO mass.sample (smp_id, submission_id, sample_name, status_id) VALUES
  -- SSUB001848 の 4 サンプル
  (1001, 'SSUB001848', 'SAMPLE-01', NULL),
  (1002, 'SSUB001848', 'SAMPLE-02', NULL),
  (1003, 'SSUB001848', 'SAMPLE-03', NULL),
  (1004, 'SSUB001848', 'SAMPLE-04', NULL),
  -- SAMD00000007 / SSUB000020 → 同一 smp_id
  (7,    'SSUB000020', 'SAMPLE-07', NULL),
  -- SAMD00025188 / SSUB003675
  (25188,'SSUB003675', 'SAMPLE-25188', NULL),
  -- SSUB000001 削除済み
  (9001, 'SSUB000001', 'DELETED-SAMPLE', 5700),
  -- SAMD00052344 / SSUB000002, smp_id 64274
  (64274,'SSUB000002', 'SAMPLE-52344', NULL),
  -- SAMD00000001 / SSUB000003
  (10001,'SSUB000003', 'SAMPLE-00001', NULL),
  -- SAMD00023002 locus_tag_prefix なし
  (23002,'SSUB000004', 'SAMPLE-23002', NULL),
  -- SAMD00060421 exists no DRA
  (60421,'SSUB000005', 'SAMPLE-60421', NULL),
  -- SAMD00032107-32157 submitter hirotoju (51 件。test_biosample_not_found が 00032108-00032156 の
  -- レンジを valid 扱いにすることを期待しているのでまとめて生成する)
  -- ※ 個別の seed INSERT ではなく後段の DO ブロックで投入する
  -- SAMD00052345 / SSUB000007
  (52345,'SSUB000007', 'SAMPLE-52345', NULL),
  -- smp_id 104969 for test_get_bioproject_id_via_dra
  (104969,'SSUB000002', 'SAMPLE-104969', NULL),
  -- test_duplicated_locus_tag_prefix 用
  (55454, 'SSUB005454', 'SAMPLE-PP14', NULL),  -- locus_tag_prefix=PP14
  (55462, 'SSUB005462', 'SAMPLE-RR1',  NULL),  -- locus_tag_prefix=RR1
  -- test_get_biosample_info 用 (note/derived_from で別 BioSample を参照するケース)
  (81372, 'SSUB_REF', 'SAMPLE-81372', NULL),
  (56903, 'SSUB_REF', 'SAMPLE-56903', NULL),
  (56904, 'SSUB_REF', 'SAMPLE-56904', NULL),
  (80626, 'SSUB_REF', 'SAMPLE-80626', NULL),
  (80628, 'SSUB_REF', 'SAMPLE-80628', NULL);

-- accession: smp_id ⇄ SAMD accession_id
INSERT INTO mass.accession (smp_id, accession_id) VALUES
  (7,     'SAMD00000007'),
  (25188, 'SAMD00025188'),
  (64274, 'SAMD00052344'),
  (52345, 'SAMD00052345'),
  (10001, 'SAMD00000001'),
  (23002, 'SAMD00023002'),
  (60421, 'SAMD00060421'),
  (81372, 'SAMD00081372'),
  (56903, 'SAMD00056903'),
  (56904, 'SAMD00056904'),
  (80626, 'SAMD00080626'),
  (80628, 'SAMD00080628');

-- attribute (locus_tag_prefix / metadata 用)
INSERT INTO mass.attribute (smp_id, attribute_name, attribute_value, seq_no) VALUES
  -- SAMD00000007 / SSUB000020: locus_tag_prefix = ATW
  (7,     'locus_tag_prefix', 'ATW',       1),
  -- SAMD00052344 のメタデータ (test_get_biosample_metadata が attribute_list.size > 0 を期待)
  (64274, 'bioproject_id',    'PRJDB4841', 1),
  (64274, 'collection_date',  'missing',   2),
  (64274, 'sample_name',      'sample_A',  3),
  -- SAMD00052345 も同様
  (52345, 'bioproject_id',    'PRJDB4841', 1),
  (52345, 'collection_date',  '2020-01-01',2),
  -- test_duplicated_locus_tag_prefix 用
  (55454, 'locus_tag_prefix', 'PP14', 1),
  (55462, 'locus_tag_prefix', 'RR1',  1),
  -- test_get_biosample_info: 参照 BioSample を note/derived_from 属性に埋め込む
  -- get_biosample_metadata は attribute_value != '' の行のみ返すので、参照先の BioSample にも
  -- 何か属性を付けておかないと戻り値 hash の keys.size が期待値に届かない
  (60421, 'note',             'related samples SAMD00056903 and SAMD00056904', 1),
  (81372, 'derived_from',     'Derived from SAMD00080626 / SAMD00080628',      1),
  (56903, 'sample_name',      'sample 56903', 1),
  (56904, 'sample_name',      'sample 56904', 1),
  (80626, 'sample_name',      'sample 80626', 1),
  (80628, 'sample_name',      'sample 80628', 1);

-- get_all_locus_tag_prefix が >200 行を要求するので SSUB_LTP 配下に 210 サンプル + locus_tag_prefix を生成
DO $$
DECLARE
  base_smp bigint := 200000;
BEGIN
  FOR i IN 1..210 LOOP
    INSERT INTO mass.sample    (smp_id, submission_id, sample_name) VALUES (base_smp + i, 'SSUB_LTP', 'LTP-' || i);
    INSERT INTO mass.attribute (smp_id, attribute_name, attribute_value, seq_no) VALUES (base_smp + i, 'locus_tag_prefix', 'LTP' || i, 1);
  END LOOP;
END $$;

-- SAMD00032107-32157 (hirotoju) を一括生成
DO $$
BEGIN
  FOR i IN 32107..32157 LOOP
    INSERT INTO mass.sample    (smp_id, submission_id, sample_name) VALUES (i, 'SSUB000006', 'SAMPLE-' || i);
    INSERT INTO mass.accession (smp_id, accession_id)               VALUES (i, 'SAMD' || lpad(i::text, 8, '0'));
  END LOOP;
END $$;
