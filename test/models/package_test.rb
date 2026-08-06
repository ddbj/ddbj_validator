require 'test_helper'

# パッケージ定義は gem に同梱されたので、ここは SPARQL ではなく conf/package_definitions/
# を読む。version と package_id は外から来る文字列で、そのままではパスの一部になる。
class TestPackage < ActiveSupport::TestCase
  def setup
    @package = DDBJValidator::Package.new
    @version = Rails.configuration.validator['biosample']['package_version']
  end

  def test_package_list_returns_the_packages_of_a_served_version
    ret = @package.package_list(@version)

    assert_equal 'success', ret[:status]
    assert ret[:data].any?
    assert ret[:data].first.key?(:package_id)
  end

  # 1.2.1 以前は別世代のオントロジーで、どのクエリも 0 行を返していた。同梱後も
  # 「知っているが答えられない版」と「知らない版」は応答を分ける — 分けないと、
  # 古い版を叩いているクライアントに突然「そんな版は無い」と言うことになる
  def test_a_known_but_unanswerable_version_is_not_reported_as_unknown
    known   = @package.package_list('1.2.0')
    unknown = @package.package_list('9.9.9')

    assert_equal 'error', known[:status]
    assert_equal 'fail',  unknown[:status]
    assert_match 'invalid package version', unknown[:message]
  end

  def test_attribute_list_joins_the_attribute_comments_back_in
    ret = @package.attribute_list(@version, 'MIGS.ba.soil')

    assert_equal 'success', ret[:status]
    assert ret[:data].any? { it[:attribute_comment].present? }, '版ごとに切り出した説明が戻っていない'
  end

  # package_id と version は conf/package_definitions/ 配下のパスになる。知っている
  # 名前だけを通していないと、Pathname#join が "../" をそのまま繋いで外に出る
  def test_lookups_reject_traversal
    traversal = "#{'../' * 10}etc/passwd"

    assert_equal 'fail', @package.attribute_list(@version, traversal)[:status]
    assert_equal 'fail', @package.package_info(@version, traversal)[:status]
    assert_equal 'fail', @package.package_list(traversal)[:status]
  end

  # attribute_template_file が組み立てるのは public/template/ 配下のパスで、その結果は
  # send_file にそのまま渡る。ここを塞いでいないと任意の .tsv / .xlsx を配れてしまう
  def test_attribute_template_file_rejects_traversal
    Tempfile.create(['leak', '.tsv']) do |file|
      file.write('SECRET')
      file.flush

      # public/template/<version>/bs/tsv/ から辿って外のファイルを指す
      outside = file.path.delete_suffix('.tsv')
      ret     = @package.attribute_template_file('1.4.0', "#{'../' * 30}#{outside.delete_prefix('/')}", false, 'text/tab-separated-values')

      assert_equal 'fail', ret[:status]
      assert_nil ret[:file_path]
    end
  end

  def test_attribute_template_file_rejects_an_unknown_version
    ret = @package.attribute_template_file("1.4.0/#{'../' * 5}", 'MIGS.ba.soil', false, 'text/tab-separated-values')

    assert_equal 'fail', ret[:status]
  end
end
