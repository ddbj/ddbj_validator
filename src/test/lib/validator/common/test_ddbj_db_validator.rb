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
    assert_nil @db_validator.get_bioproject_submitter_id("not id")
    ## not exist id
    assert_nil @db_validator.get_bioproject_submitter_id("PRJDB00000")

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
    ret = @db_validator.get_sample_names("SSUB003677")
    assert_equal 4, ret.size

    # not exist
    ret = @db_validator.get_sample_names("SSUB000000")
    assert_equal 0, ret.size
  end

  def test_get_bioproject_accession
    # exist data
    ret = @db_validator.get_bioproject_accession("PSUB004142")
    assert_equal "PRJDB3490", ret

    # not exist
    ## project accession IS NULL
    assert_nil @db_validator.get_bioproject_accession("PSUB004148")

    ## not exist psub id
    assert_nil @db_validator.get_bioproject_accession("PSUB000000")

    ## status 5700(deleted?)
    assert_nil @db_validator.get_bioproject_accession("PSUB000078")
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
