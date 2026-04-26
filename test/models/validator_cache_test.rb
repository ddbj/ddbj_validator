require 'test_helper'

# BioSampleValidator の各 rule が Rails.cache 経由でキャッシュを効かせていることの確認。
# test env のデフォルトは :null_store なので、ここだけ MemoryStore に差し替えて検証する。
class TestValidatorCache < Minitest::Test
  def setup
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @validator = BioSampleValidator.new
  end

  def teardown
    Rails.cache = @original_cache
    super
  end

  def test_cache_invalid_host_organism_name
    host_name = 'Homo sapiens'
    ret1 = @validator.send('invalid_host_organism_name', 'BS_R0015', 'sampleA', '', host_name, 1)
    assert Rails.cache.exist?(['exist_organism_name', host_name])
    ret2 = @validator.send('invalid_host_organism_name', 'BS_R0015', 'sampleA', '9606', 'Homo sapiens', 1)
    assert_equal ret1, ret2
  end

  def test_cache_taxonomy_error_warning
    organism_name = 'Homo sapiens'
    ret1 = @validator.send('taxonomy_error_warning', 'BS_R0045', 'sampleA', organism_name, 1)
    assert_equal({status: 'exist', tax_id: '9606', scientific_name: 'Homo sapiens'},
                 Rails.cache.read(['exist_organism_name', organism_name]))
    ret2 = @validator.send('taxonomy_error_warning', 'BS_R0045', 'sampleA', organism_name, 1)
    assert_equal ret1, ret2
  end

  def test_cache_get_attributes_of_package
    package_name    = 'MIGS.ba.soil'
    package_version = @validator.instance_variable_get(:@package_version)

    ret1 = @validator.send('get_attributes_of_package', package_name, package_version)
    assert Rails.cache.exist?(['package_attributes', package_name])
    ret2 = @validator.send('get_attributes_of_package', package_name, package_version)
    assert_equal ret1, ret2
  end

  def test_cache_unknown_package
    package_name    = 'MIGS.ba.soil'
    package_version = @validator.instance_variable_get(:@package_version)

    ret1 = @validator.send('unknown_package', 'BS_R0026', 'sampleA', package_name, package_version, 1)
    assert Rails.cache.exist?(['unknown_package', package_name])
    ret2 = @validator.send('unknown_package', 'BS_R0026', 'sampleA', package_name, package_version, 1)
    assert_equal ret1, ret2
  end

  def test_cache_invalid_publication_identifier
    ref_attr = JSON.parse(File.read(Rails.root.join('conf/biosample/reference_attributes.json')))
    pubchem_id = '27148491'
    ret1 = @validator.send('invalid_publication_identifier', 'BS_R0011', 'SampleA', 'ref_biomaterial', pubchem_id, ref_attr, 1)
    assert Rails.cache.exist?(['exist_pubchem_id', pubchem_id])
    ret2 = @validator.send('invalid_publication_identifier', 'BS_R0011', 'SampleA', 'ref_biomaterial', pubchem_id, ref_attr, 1)
    assert_equal ret1, ret2
  end

  def test_chach_package_versus_organism
    # ok case
    taxonomy_id = '103690'
    package_name = 'MIGS.ba.microbial'
    organism_name = 'Nostoc sp. PCC 7120'
    ret1 = @validator.send('package_versus_organism', 'BS_R0048', 'SampleA', taxonomy_id, package_name, organism_name, 1)
    assert Rails.cache.exist?(['tax_vs_package', taxonomy_id, package_name])
    ret2 = @validator.send('package_versus_organism', 'BS_R0048', 'SampleA', taxonomy_id, package_name, organism_name, 1)
    assert_equal ret1, ret2

    # ng case
    taxonomy_id = '9606'
    package_name = 'MIGS.ba.microbial'
    organism_name = 'Homo sapiens'
    ret3 = @validator.send('package_versus_organism', 'BS_R0048', 'SampleA', taxonomy_id, package_name, organism_name, 1)
    assert Rails.cache.exist?(['tax_vs_package', taxonomy_id, package_name])
    ret4 = @validator.send('package_versus_organism', 'BS_R0048', 'SampleA', taxonomy_id, package_name, organism_name, 1)
    assert_equal ret3, ret4
  end

  def test_cache_taxonomy_name_and_id_not_match
    taxonomy_id = '103690'
    organism_name = 'Nostoc sp. PCC 7120'
    ret1 = @validator.send('taxonomy_name_and_id_not_match', 'BS_R0004', 'SampleA', taxonomy_id, organism_name, 1)
    assert Rails.cache.exist?(['tax_match_organism', taxonomy_id])
    ret2 = @validator.send('taxonomy_name_and_id_not_match', 'BS_R0004', 'SampleA', taxonomy_id, organism_name, 1)
    assert_equal ret1, ret2
  end

  def test_cache_sex_for_bacteria
    bac_vir_linages = [OrganismValidator::TAX_BACTERIA, OrganismValidator::TAX_VIRUSES]
    fungi_linages = [OrganismValidator::TAX_FUNGI]

    taxonomy_id = '103690'
    sex = 'male'
    organism_name = 'Nostoc sp. PCC 7120'
    ret1 = @validator.send('sex_for_bacteria', 'BS_R0059', 'SampleA', taxonomy_id, sex, organism_name, 1)
    assert Rails.cache.exist?(['tax_has_linage', taxonomy_id, bac_vir_linages])
    ret2 = @validator.send('sex_for_bacteria', 'BS_R0059', 'SampleA', taxonomy_id, sex, organism_name, 1)
    assert_equal ret1, ret2

    taxonomy_id = '1445577'
    organism_name = 'Colletotrichum fioriniae PJ7'
    ret3 = @validator.send('sex_for_bacteria', 'BS_R0059', 'SampleA', taxonomy_id, sex, organism_name, 1)
    assert Rails.cache.exist?(['tax_has_linage', taxonomy_id, fungi_linages])
    ret4 = @validator.send('sex_for_bacteria', 'BS_R0059', 'SampleA', taxonomy_id, sex, organism_name, 1)
    assert_equal ret3, ret4
  end
end
