require 'json'
require 'yaml'
require 'bundler/setup'
require 'minitest/autorun'
require '../../../../lib/validator/common/ddbj_db_validator.rb'

class TestDDBJDbValidator < Minitest::Test

  def setup
    conf_dir = File.expand_path('../../../../../conf', __FILE__)
    setting = YAML.load(File.read(conf_dir + "/validator.yml"))
    db_config = setting["ddbj_rdb"]
    @db_validator = DDBJDbValidator.new(db_config)
  end

  def test_valid_bioproject_id?
    # exist data
    ##PSUB
    ret = @db_validator.valid_bioproject_id?("PSUB004141")
    assert_equal true, ret
    ##PRJDB
    ret = @db_validator.valid_bioproject_id?("PRJDB3490")
    assert_equal true, ret

    # not exist data
    ##invalid ID
    ret = @db_validator.valid_bioproject_id?("not id")
    assert_equal false, ret
    ## not exist id
    ret = @db_validator.valid_bioproject_id?("PRJDB00000")
    assert_equal false, ret
    ## sql injection
    ret = @db_validator.valid_bioproject_id?("PSUB004141' OR '1' = '1")
    assert_equal false, ret

  end

  def test_get_bioproject_referenceable_submitter_ids
    # exist data
    ##PSUB
    ret = @db_validator.get_bioproject_referenceable_submitter_ids("PSUB004388")
    assert_equal 2, ret.size
    ##PRJDB
    ret = @db_validator.get_bioproject_referenceable_submitter_ids("PRJDB3595")
    assert_equal 2, ret.size
    ##PRJNA71719
    ret = @db_validator.get_bioproject_referenceable_submitter_ids("PRJNA71719")
    assert_equal 1, ret.size

    # not exist data
    ##invalid ID
    assert_equal [], @db_validator.get_bioproject_referenceable_submitter_ids("not id")
    ## not exist id
    assert_equal [], @db_validator.get_bioproject_referenceable_submitter_ids("PRJDB00000")
    ## sql injection
    assert_equal [], @db_validator.get_bioproject_referenceable_submitter_ids("PSUB004141' OR '1' = '1")
  end

  def test_umbrella_project?
    # true case
    ##PSUB
    ret = @db_validator.umbrella_project?("PSUB001851")
    assert_equal true, ret
    ##PRJDB
    ret = @db_validator.umbrella_project?("PRJDB1554")
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

  def test_get_bioproject_names
    # exist case
    ret = @db_validator.get_bioproject_names("ddbj_ffpri")
    assert_equal 1, ret.size
    # not exist case
    ret = @db_validator.get_bioproject_names("not_exist_submitter")
    assert_equal 0, ret.size
  end

  def test_get_bioproject_title_descs
    # exist case
    ret = @db_validator.get_bioproject_title_descs("ddbj_ffpri")
    assert_equal 1, ret.size
    expected_text = "Diurnal transcriptome dynamics of Japanese cedar (Cryptomeria japonica) in summer and winter,We constracted cDNA library form the RNA mixture which were isolated from Japanese cedar shoots sampled throughout the day and year, and analyzed by Roche 454 GS FLX.  The sequence data was used to design microarray probes. The seasonal and diurnal transcriptome dynamics were investigated by this new designed microarray."
    assert_equal expected_text, ret.first
    # not exist case
    ret = @db_validator.get_bioproject_title_descs("not_exist_submitter")
    assert_equal 0, ret.size
  end

  def test_get_sample_names
    # exist data
    ret = @db_validator.get_sample_names("SSUB001848")
    assert_equal 4, ret.size

    # not exist
    ret = @db_validator.get_sample_names("SSUB000000")
    assert_equal 0, ret.size
  end

  def test_get_bioproject_accession
    # exist data
    ret = @db_validator.get_bioproject_accession("PSUB004141")
    assert_equal "PRJDB3490", ret

    # not exist
    ## project accession IS NULL
    assert_nil @db_validator.get_bioproject_accession("PSUB004148")

    ## not exist psub id
    assert_nil @db_validator.get_bioproject_accession("PSUB000000")

    ## status 5700(deleted?)
    assert_nil @db_validator.get_bioproject_accession("PSUB000078")
  end

  def test_get_bioproject_submission
    # exist data
    ret = @db_validator.get_bioproject_submission("PRJDB3490")
    assert_equal "PSUB004141", ret

    # not exist
    ## not exist accession id
    assert_nil @db_validator.get_bioproject_accession("PRJDB00")

    ## project accession is not valid format
    assert_nil @db_validator.get_bioproject_accession("PRJE3490")


    ## status 5700(deleted?)
    assert_nil @db_validator.get_bioproject_accession("PRJDB51")
  end

  def test_get_all_locus_tag_prefix
    ret = @db_validator.get_all_locus_tag_prefix()
    assert_equal true, ret.size > 200
  end

  def test_get_biosample_locus_tag_prefix
    # exist data
    ret = @db_validator.get_biosample_locus_tag_prefix("SAMD00000007")
    assert_equal "ATW", ret[0]["locus_tag_prefix"]
    ret = @db_validator.get_biosample_locus_tag_prefix("SSUB000020")
    assert_equal "ATW", ret[0]["locus_tag_prefix"]

    # not exist
    ## not exist sample id
    assert_nil @db_validator.get_biosample_locus_tag_prefix("SAMD0000000")
    ## not exist psub id
    assert_nil @db_validator.get_biosample_locus_tag_prefix("SSUB000000")

    ## sample exit but has not locus_tag_prefix attr
    assert_nil @db_validator.get_biosample_locus_tag_prefix("SAMD00023002")

  end

  def test_is_valid_biosample_id
    # exist data
    ret = @db_validator.is_valid_biosample_id?("SAMD00025188")
    assert_equal true, ret
    ret = @db_validator.is_valid_biosample_id?("SSUB003675")
    assert_equal true, ret

    # not exist
    ## not exist sample id
    ret = @db_validator.is_valid_biosample_id?("SAMD0000000")
    assert_equal false, ret
    ## not exist psub id
    ret = @db_validator.is_valid_biosample_id?("SSUB000000")
    assert_equal false, ret

    ## status 5700(deleted?)
    ret = @db_validator.is_valid_biosample_id?("SSUB000001")
    assert_equal false, ret
  end

  def test_get_all_locus_tag_prefix
    ret = @db_validator.get_all_locus_tag_prefix()
  end

  def test_get_submitter_organization
    # exist id
    ret = @db_validator.get_submitter_organization("test01")
    assert_equal "test01", ret["submitter_id"]
    assert_equal "National Institute of Genetics", ret["center_name"]
    assert_equal "DNA Data Bank of Japan", ret["organization"]
    assert_equal "Database Division", ret["department"]
    assert_equal "affiliation name", ret["affiliation"]
    assert_equal "unit name", ret["unit"]

    # not exist id
    assert_nil @db_validator.get_submitter_organization("not id")

  end

  def test_get_submitter_center_name
    # exist id
    ret = @db_validator.get_submitter_center_name("test01")
    assert_equal "National Institute of Genetics", ret
    # exist id but not has center_name
    ret = @db_validator.get_submitter_center_name("test02")
    assert_nil ret

    # not exist id
    assert_nil @db_validator.get_submitter_center_name("not id")

  end

  def test_get_submitter_contact_list
    # exist id
    ret = @db_validator.get_submitter_contact_list("test01")
    ret = ret[0]
    assert_equal "test01", ret["submitter_id"]
    assert_equal "test@mail.com", ret["email"]
    assert_equal "Taro", ret["first_name"]
    assert_equal "Genome", ret["middle_name"]
    assert_equal "Mishima", ret["last_name"]

    # not exist id
    assert_nil @db_validator.get_submitter_contact_list("not id")
  end

end
