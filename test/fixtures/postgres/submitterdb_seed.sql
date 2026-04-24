-- submitterdb seed: test_get_submitter_organization / _center_name / _contact_list

INSERT INTO mass.organization (submitter_id, center_name, organization, department, affiliation, unit) VALUES
  ('test01', 'National Institute of Genetics', 'DNA Data Bank of Japan', 'Database Division', 'affiliation name', 'unit name'),
  ('test02',  NULL, 'DDBJ (no center)', NULL, NULL, NULL);

INSERT INTO mass.contact (cnt_id, submitter_id, email, first_name, middle_name, last_name, is_pi) VALUES
  (1, 'test01', 'test@mail.com', 'Taro', 'Genome', 'Mishima', true);
