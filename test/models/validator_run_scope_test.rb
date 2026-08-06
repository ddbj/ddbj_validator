require 'test_helper'

# 中央 PostgreSQL から引いた答えの寿命。
#
# 検証 1 回のあいだは使い回す (同じ BioProject を参照するサンプルが 1000 あっても
# 問い合わせは 1 回)。検証をまたいでは持ち越さない — キュレータが umbrella フラグを
# 立てても submitter を変えても随時変わるデータで、以前は DDBJValidator.cache に
# 載せていたためプロセスが生きているあいだ古い答えを返し続けていた。
class TestValidatorRunScope < ActiveSupport::TestCase
  def setup
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  def teardown
    Rails.cache = @original_cache
    super
  end

  def test_a_run_asks_the_central_db_once
    validator = DDBJValidator::BioSampleValidator.new
    asked     = 0

    stub_db_validator(validator, umbrella_project?: ->(_accession) { asked += 1; false })

    3.times {|i| validator.send('invalid_bioproject_type', 'BS_R0028', "sample#{i}", 'PRJDB1', i + 1) }

    assert_equal 1, asked, '同じ検証の中では 1 回だけ引く'
  end

  def test_the_next_run_asks_again
    asked = 0

    2.times do
      validator = DDBJValidator::BioSampleValidator.new

      stub_db_validator(validator, umbrella_project?: ->(_accession) { asked += 1; false })
      validator.send('invalid_bioproject_type', 'BS_R0028', 'sampleA', 'PRJDB1', 1)
    end

    assert_equal 2, asked, '検証をまたいだら引き直す (随時変わるデータなので)'
  end

  # ホストのキャッシュに載せてしまうと、プロセスの寿命ぶん古い答えが残る
  def test_the_central_db_answer_does_not_reach_the_host_cache
    validator = DDBJValidator::BioSampleValidator.new

    stub_db_validator(validator, umbrella_project?: ->(_accession) { false })
    validator.send('invalid_bioproject_type', 'BS_R0028', 'sampleA', 'PRJDB1', 1)

    assert_empty Rails.cache.instance_variable_get(:@data).keys.grep(/umbrella/)
  end
end
