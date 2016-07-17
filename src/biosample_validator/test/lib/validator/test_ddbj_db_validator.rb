require 'json'
require 'bundler/setup'
require 'minitest/autorun'
require '../../../lib/validator/ddbj_db_validator.rb'

class TestDDBJDbValidator < Minitest::Test

  def setup
    db_config = JSON.parse(File.read(File.dirname(__FILE__) + "/../../../conf/ddbj_db_config.json"))
    @db_validator = DDBJDbValidator.new(db_config)
  end

  def test_get_bioproject_submitter_id
    # exist data
    ##PSUB
    ret = @db_validator.get_bioproject_submitter_id("PSUB004142")
    assert_equal "PRJDB3490", ret["bioproject_accession"]
    assert_equal "PSUB004142", ret["submission_id"]
    assert_equal "test01", ret["submitter_id"]
    ##PRJDB
    ret = @db_validator.get_bioproject_submitter_id("PRJDB3490")
    assert_equal "PRJDB3490", ret["bioproject_accession"]
    assert_equal "PSUB004142", ret["submission_id"]
    assert_equal "test01", ret["submitter_id"]

    # not exist data
    ##invalid ID
    ret = @db_validator.get_bioproject_submitter_id("not id")
    assert_equal nil, ret
    ## not exist id
    ret = @db_validator.get_bioproject_submitter_id("PRJDB00000")
    assert_equal nil, ret

  end

  def test_umbrella_project?
    # true case
    ##PSUB
    ret = @db_validator.umbrella_project?("PSUB990036")
    assert_equal true, ret
    ##PRJDB
    ret = @db_validator.umbrella_project?("PRJDB3549")
    assert_equal true, ret
    # false case
    ##PSUB
    ret = @db_validator.umbrella_project?("PSUB004142")
    assert_equal false, ret
    ##PRJDB
    ret = @db_validator.umbrella_project?("PRJDB3490")
    assert_equal false, ret
    ## not exist id
    ret = @db_validator.umbrella_project?("PSUB000000")
    assert_equal false, ret
    ret = @db_validator.umbrella_project?("PRJDB0000")
    assert_equal false, ret
    ## invalid id
    ret = @db_validator.umbrella_project?("PRJNA0000")
    assert_equal false, ret

  end

  def test_get_bioproject_accession
    # ok case
    ret = @db_validator.get_bioproject_accession("PSUB004142")
    assert_equal "PRJDB3490", ret

    # ng case
    ## project accession IS NULL
    ret = @db_validator.get_bioproject_accession("PSUB004148")
    assert_equal nil, ret

    ## not exist psub id
    ret = @db_validator.get_bioproject_accession("PSUB000000")
    assert_equal nil, ret

    ## status 5700(deleted?)
    ret = @db_validator.get_bioproject_accession("PSUB000078")
    assert_equal nil, ret
  end

  def test_get_all_locus_tag_prefix
    ret = @db_validator.get_all_locus_tag_prefix()
    assert_equal true, ret.size > 200
  end
end
