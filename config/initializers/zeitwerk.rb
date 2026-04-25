# lib/ 配下を Zeitwerk autoload に乗せるための調整。
#
# - collapse: ディレクトリを namespace にせず、全ファイルが top-level 定数を
#   定義する現状の構造をそのまま許容する。将来 app/models 等に移すタイミング
#   で proper namespace 化する。
# - inflect: ファイル名と定数名がデフォルト規則で一致しない箇所を明示する
#   (acronym, BioSample/BioProject の camel hump 等)。
loader = Rails.autoloaders.main

loader.collapse(
  Rails.root.join('lib/validator'),
  Rails.root.join('lib/validator/common'),
  Rails.root.join('lib/validator/auto_annotator'),
  Rails.root.join('lib/submitter'),
  Rails.root.join('lib/package')
)

loader.inflector.inflect(
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
