# lib/validator, lib/submitter, lib/package は Zeitwerk 命名規約に揃っていない (BioSampleValidator
# vs biosample_validator.rb 等) ので、Rails の autoload には載せず明示的に require する。
# Phase 4 で lib/ を Zeitwerk 対応の命名/名前空間に整理したらこの初期化ファイルは不要になる。
require Rails.root.join('lib/validator/validator')
require Rails.root.join('lib/validator/biosample_validator')
require Rails.root.join('lib/validator/auto_annotator/auto_annotator')
require Rails.root.join('lib/submitter/submitter')
require Rails.root.join('lib/package/package')
