require 'fileutils'
require 'test_helper'

class TestCollDump < ActiveSupport::TestCase
  def test_parse
    file_name = 'coll_dump.txt'
    # get file (first run downloads from NCBI)
    FileUtils.rm(file_name) if File.exist?(file_name)
    ret = CollDump.parse(file_name)
    assert_equal true, ret[:specimen_voucher].include?('UWBM')
    assert_equal true, ret[:culture_collection].include?('ATCC')
    assert_equal true, ret[:bio_material].include?('CIAT')
    assert_equal true, ret[:bio_material].include?('CIAT:Bean')
    assert_equal true, ret[:bio_material].include?('ANDES:T')

    # second call reuses the already-downloaded file
    ret = CollDump.parse(file_name)
    assert_equal true, ret[:specimen_voucher].include?('UWBM')
    assert_equal true, ret[:culture_collection].include?('ATCC')
  ensure
    FileUtils.rm(file_name) if File.exist?(file_name)
  end
end
