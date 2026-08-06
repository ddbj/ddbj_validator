require 'fileutils'
require 'minitest/mock'
require 'tmpdir'
require 'test_helper'

class TestCollDump < ActiveSupport::TestCase
  # 以前はここで実際に NCBI FTP から coll_dump.txt を落としていた。毎回消してから
  # 取り直すので、スイートが数十秒延びるうえ NCBI が不調な日に落ち、しかも相対パスの
  # ため成果物がリポジトリ直下に残っていた。パースの確認に通信は要らない。
  FIXTURE = Rails.root.join('test/fixtures/conf/coll_dump/coll_dump.txt')

  def test_parse
    ret = DDBJValidator::CollDump.parse(FIXTURE.to_s)

    assert_includes ret[:specimen_voucher],   'UWBM'
    assert_includes ret[:culture_collection], 'ATCC'
    assert_includes ret[:bio_material],       'CIAT'
    assert_includes ret[:bio_material],       'CIAT:Bean'
    assert_includes ret[:bio_material],       'ANDES:T'
  end

  # 取得済みのファイルがあれば読むだけで、取りに行かない
  def test_parse_does_not_download_when_the_file_is_there
    ret = Net::FTP.stub :new, ->(*) { flunk 'ファイルがあるのにダウンロードしようとした' } do
      DDBJValidator::CollDump.parse(FIXTURE.to_s)
    end

    assert_includes ret[:culture_collection], 'ATCC'
  end

  # 落とせなかったことを「該当なし」にしない。参照データ無しで検証を続けると
  # specimen_voucher / culture_collection のチェックが黙って効かなくなる
  def test_a_failed_download_is_an_endpoint_error
    Dir.mktmpdir('coll_dump_test') do |dir|
      missing = File.join(dir, 'coll_dump.txt')

      Net::FTP.stub :new, ->(*) { raise SocketError, 'getaddrinfo failed' } do
        assert_raises DDBJValidator::EndpointUnavailable do
          DDBJValidator::CollDump.parse(missing)
        end
      end

      assert_empty Dir.glob(File.join(dir, '*')), '途中で切れたファイルを残さない'
    end
  end
end
