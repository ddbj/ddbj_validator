require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'geocoder'
require 'date'
require 'net/http'
require File.dirname(__FILE__) + "/base.rb"
require File.dirname(__FILE__) + "/common/common_utils.rb"
require File.dirname(__FILE__) + "/common/date_format.rb"
require File.dirname(__FILE__) + "/common/ddbj_db_validator.rb"
require File.dirname(__FILE__) + "/common/organism_validator.rb"
require File.dirname(__FILE__) + "/common/sparql_base.rb"
require File.dirname(__FILE__) + "/common/validator_cache.rb"
require File.dirname(__FILE__) + "/common/xml_convertor.rb"

#
# A class for JVar validation
#
class JVarValidator < ValidatorBase
  attr_reader :error_list

  #
  # Validate the all rules for the jvar data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # data_vcf: VCF file path
  #
  #
  def validate (data_vcf, submitter_id=nil)
    # とりあえずJSON converterのみ実装
    # 必要ならpython版validatorの呼び出し
    @error_list = error_list = []
  end
end