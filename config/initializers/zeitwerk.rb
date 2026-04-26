# app/models/ 配下はフラット (BioSampleValidator など top-level 定数のみ) なので、
# ファイル名と定数名がデフォルト規則で一致しない箇所だけ inflector に明示する。
Rails.autoloaders.main.inflector.inflect(
  'biosample_validator'       => 'BioSampleValidator',
  'biosample_submitter'       => 'BioSampleSubmitter',
  'bioproject_validator'      => 'BioProjectValidator',
  'bioproject_tsv_validator'  => 'BioProjectTsvValidator',
  'bioproject_submitter'      => 'BioProjectSubmitter',
  'jvar_validator'            => 'JVarValidator',
  'metabobank_idf_validator'  => 'MetaboBankIdfValidator',
  'metabobank_sdrf_validator' => 'MetaboBankSdrfValidator',
  'ddbj_db_validator'         => 'DDBJDbValidator',
  'sparql'                    => 'SPARQL',
  'sparql_base'               => 'SPARQLBase',
  'excel2tsv'                 => 'Excel2Tsv'
)
