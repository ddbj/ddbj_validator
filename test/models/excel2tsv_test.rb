require 'fileutils'
require 'tempfile'
require 'tmpdir'
require 'test_helper'

class TestExcel2Tsv < ActiveSupport::TestCase
  def setup
    @excel2tsv = DDBJValidator::Excel2Tsv.new
    @test_file_dir = Rails.root.join('test/data/all_data')
    # テストは 32 プロセス並列で走るので、出力先を共有すると互いの成果物を
    # 消し合う。プロセスごとに別ディレクトリを取れば競合しないし、
    # test/data 配下に成果物も残らない
    @base_dir = Pathname.new(Dir.mktmpdir('excel2tsv_test'))
  end

  def teardown
    FileUtils.rm_rf(@base_dir)
  end

  # 拡張子が .xlsx でないと roo は TypeError を、上限を超えた workbook では
  # Roo::Error ですらない ExceedsMaxError を上げる。どちらも投稿者が直せる問題なので
  # finding にする — 例外のまま抜けると 500 になり、投稿者には何も分からない
  def test_split_sheet_rejects_a_non_xlsx_extension_as_a_finding
    base_dir = output_dir('non_xlsx')

    Tempfile.create(['submission', '.xls']) do |file|
      file.write('not an excel file')
      file.flush

      ret = @excel2tsv.split_sheet(file.path, base_dir)

      assert_equal 'failed', ret[:status]
      assert_equal 1, ret[:error_list].size
    end
  end

  def test_split_sheet
    # ok case
    excel_file = "#{@test_file_dir}/bpbs_test_warning.xlsx"
    base_dir = output_dir('ok')

    ret = @excel2tsv.split_sheet(excel_file, base_dir)
    assert File.exist?("#{base_dir}/bioproject/bpbs_test_warning_bioproject.tsv")
    assert File.exist?("#{base_dir}/biosample/bpbs_test_warning_biosample.tsv")
    assert_equal 'bpbs_test_warning_bioproject.tsv', ret[:filetypes][:bioproject].split('/').last
    assert_equal 'bpbs_test_warning_biosample.tsv', ret[:filetypes][:biosample].split('/').last

    # ng base
    excel_file = "#{@test_file_dir}/invalid_excel.xlsx" # 中身はただのTextファイル
    base_dir = output_dir('invalid')

    ret = @excel2tsv.split_sheet(excel_file, base_dir)
    assert_equal 'failed', ret[:status]
    assert_equal 1, ret[:error_list].size
    assert !File.exist?("#{base_dir}/bioproject")
    assert !File.exist?("#{base_dir}/biosample")

    # 関数とセル結合のあるファイルがパースできるか
    excel_file = "#{@test_file_dir}/bioproject_test_merge_cells.xlsx"
    base_dir = output_dir('merge_cells')

    ret = @excel2tsv.split_sheet(excel_file, base_dir)
    tsv_file = "#{base_dir}/bioproject/bioproject_test_merge_cells_bioproject.tsv"
    tsv_data = CSV.read(tsv_file, encoding: 'UTF-8:UTF-8', col_sep: "\t")
    tsv_data.each do |row|
      if row[0] == 'organization'
        # 結合されていた全てのセルに同じ値が入っている事を期待
        assert_equal 'DDBJ', row[1]
        assert_equal 'DDBJ', row[2]
      elsif row[0] == 'isolate' # =B22 の数式で得た値が取得できる事を期待
        assert_equal 'N.A.', row[1]
      elsif row[0] == 'cultivar' # 文字列の表記の為に先頭にアポストロフィーを付与している"'123"。それは除去できていて欲しい
        assert_equal '123', row[1]
      elsif row[0] == 'breed' # 計算式を使用。"123/10 = 12.3"の数値で取得する？文字列？
        assert_equal '12.3', row[1]
        # assert_equal "12.3000", row[2] #書式設定通りに取得できるか？ => 書式設定は落とされて"12.3"で取得する
      elsif row[0] == 'strain' # 日付の入力取得。表記のままの文字列で取得できる？
        # assert_equal "2022/3/7", row[1]
        assert_equal '2022-03-07', row[1] # => こういう形式で取得する
      elsif row[0] == 'doi' # 関数の使用 "=IF(B23="1111","o","x")
        assert_equal 'o', row[1]
      end
    end
    FileUtils.rm_rf(base_dir)

    # macro付きExcelがパース出来、かつmacroが実行されないか
    excel_file = "#{@test_file_dir}/bioproject_test_with_macro.xlsm"
    base_dir = output_dir('macro')

    ret = @excel2tsv.split_sheet(excel_file, base_dir)
    tsv_file = "#{base_dir}/bioproject/bioproject_test_with_macro_bioproject.tsv"
    tsv_data = CSV.read(tsv_file, encoding: 'UTF-8:UTF-8', col_sep: "\t")
    tsv_data.each do |row|
      if row[0] == 'first_name'
        assert_equal 'will update by macro', row[1] # 起動時のマクロによって値が"YAMADA"に上書きされる設定だが、これが効かない事を確認する
      elsif row[0] == 'organization'
        # 結合されていた全てのセルに同じ値が入っている事を期待
        assert_equal 'DDBJ', row[1]
        assert_equal 'DDBJ', row[2]
      end
    end
  end

  def test_mandatory_sheet_check
    # ok case
    sheet_settings = {
      'bioproject' => 'BioProject',
      'biosample' => 'BioSample',
      'metabobank_idf' => 'Study (IDF)',
      'metabobank_sdrf' => 'Assay (SDRF)'
    }
    mandatory_filetypes = ['biosample', 'bioproject']
    exist_sheet_list = ['BioProject', 'BioSample', 'Study (IDF)']
    ret = @excel2tsv.mandatory_sheet_check(mandatory_filetypes, exist_sheet_list, sheet_settings)
    assert ret

    # ng case
    ## missng BioSample sheet
    mandatory_filetypes = ['biosample', 'bioproject']
    exist_sheet_list = ['BioProject']
    ret = @excel2tsv.mandatory_sheet_check(mandatory_filetypes, exist_sheet_list, sheet_settings)
    assert_equal false, ret

    # ng case
    ## missng BioProject and BioSample sheets
    mandatory_filetypes = ['biosample', 'bioproject']
    exist_sheet_list = ['HELP']
    ret = @excel2tsv.mandatory_sheet_check(mandatory_filetypes, exist_sheet_list, sheet_settings)
    assert_equal false, ret
  end

  private

  # ケースごとに空のディレクトリを渡す。「何も出力されていないこと」を見るケースが
  # あるので、使い回して消すのではなく最初から別の場所を使う
  def output_dir (name)
    @base_dir.join(name).tap(&:mkpath)
  end
end
