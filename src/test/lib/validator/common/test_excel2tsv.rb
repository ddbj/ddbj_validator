require 'bundler/setup'
require 'minitest/autorun'
require 'fileutils'
require '../../../../lib/validator/common/common_utils.rb'
require '../../../../lib/validator/common/excel2tsv.rb'

class TestExcel2Tsv < Minitest::Test
  def setup
    @excel2tsv = Excel2Tsv.new
    @test_file_dir = File.expand_path('../../../../data/all_data', __FILE__)
  end

  def test_split_sheet
    # ok case
    excel_file = "#{@test_file_dir}/bpbs_test_warning.xlsx"
    base_dir = "#{@test_file_dir}/output"
    # 出力ディレクトの初期化
    if File.exist?(base_dir)
      FileUtils.rm_rf(base_dir)
    end
    FileUtils.mkdir_p(base_dir)

    ret = @excel2tsv.split_sheet(excel_file, base_dir)
    assert File.exist?("#{base_dir}/bioproject/bpbs_test_warning_bioproject.tsv")
    assert File.exist?("#{base_dir}/biosample/bpbs_test_warning_biosample.tsv")
    assert_equal "bpbs_test_warning_bioproject.tsv", ret[:filetypes][:bioproject].split("/").last
    assert_equal "bpbs_test_warning_biosample.tsv", ret[:filetypes][:biosample].split("/").last

    # ng base
    excel_file = "#{@test_file_dir}/invalid_excel.xlsx" # 中身はただのTextファイル
    base_dir = "#{@test_file_dir}/output"
    # 出力ディレクトの初期化
    if File.exist?(base_dir)
      FileUtils.rm_rf(base_dir)
    end
    FileUtils.mkdir_p(base_dir)

    ret = @excel2tsv.split_sheet(excel_file, base_dir)
    assert_equal "failed", ret[:status]
    assert_equal 1, ret[:error_list].size
    assert !File.exist?("#{base_dir}/bioproject")
    assert !File.exist?("#{base_dir}/biosample")
    FileUtils.rm_rf(base_dir)

    # 関数とセル結合のあるファイルがパースできるか
    excel_file = "#{@test_file_dir}/bioproject_test_merge_cells.xlsx"
    base_dir = "#{@test_file_dir}/output"
    # 出力ディレクトの初期化
    if File.exist?(base_dir)
      FileUtils.rm_rf(base_dir)
    end
    FileUtils.mkdir_p(base_dir)

    ret = @excel2tsv.split_sheet(excel_file, base_dir)
    tsv_file = "#{base_dir}/bioproject/bioproject_test_merge_cells_bioproject.tsv"
    tsv_data = CSV.read(tsv_file, encoding: "UTF-8:UTF-8", col_sep: "\t")
    tsv_data.each do |row|
      if row[0] == "organization"
        # 結合されていた全てのセルに同じ値が入っている事を期待
        assert_equal "DDBJ", row[1]
        assert_equal "DDBJ", row[2]
      elsif row[0] == "isolate" # =B22 の数式で得た値が取得できる事を期待
        assert_equal "N.A.", row[1]
      elsif row[0] == "cultivar" #文字列の表記の為に先頭にアポストロフィーを付与している"'123"。それは除去できていて欲しい
        assert_equal "123", row[1]
      elsif row[0] == "breed" #計算式を使用。"123/10 = 12.3"の数値で取得する？文字列？
        assert_equal "12.3", row[1]
        #assert_equal "12.3000", row[2] #書式設定通りに取得できるか？ => 書式設定は落とされて"12.3"で取得する
      elsif row[0] == "strain" # 日付の入力取得。表記のままの文字列で取得できる？
        #assert_equal "2022/3/7", row[1]
        assert_equal "2022-03-07", row[1] # => こういう形式で取得する
      elsif row[0] == "doi" # 関数の使用 "=IF(B23="1111","o","x")
        assert_equal "o", row[1]
      end
    end
    FileUtils.rm_rf(base_dir)

    # macro付きExcelがパース出来、かつmacroが実行されないか
    excel_file = "#{@test_file_dir}/bioproject_test_with_macro.xlsm"
    base_dir = "#{@test_file_dir}/output"
    # 出力ディレクトの初期化
    if File.exist?(base_dir)
      FileUtils.rm_rf(base_dir)
    end
    FileUtils.mkdir_p(base_dir)

    ret = @excel2tsv.split_sheet(excel_file, base_dir)
    tsv_file = "#{base_dir}/bioproject/bioproject_test_with_macro_bioproject.tsv"
    tsv_data = CSV.read(tsv_file, encoding: "UTF-8:UTF-8", col_sep: "\t")
    tsv_data.each do |row|
      if row[0] == "first_name"
        assert_equal "will update by macro", row[1] # 起動時のマクロによって値が"YAMADA"に上書きされる設定だが、これが効かない事を確認する
      elsif row[0] == "organization"
        # 結合されていた全てのセルに同じ値が入っている事を期待
        assert_equal "DDBJ", row[1]
        assert_equal "DDBJ", row[2]
      end
    end
    FileUtils.rm_rf(base_dir)

  end

  def test_mandatory_sheet_check
    # ok case
    sheet_settings = {
      "bioproject" => "BioProject",
      "biosample" => "BioSample",
      "metabobank_idf" => "Study (IDF)",
      "metabobank_sdrf" => "Assay (SDRF)"
    }
    mandatory_filetypes = ["biosample", "bioproject"]
    exist_sheet_list = ["BioProject", "BioSample", "Study (IDF)"]
    ret = @excel2tsv.mandatory_sheet_check(mandatory_filetypes, exist_sheet_list, sheet_settings)
    assert ret

    # ng case
    ## missng BioSample sheet
    mandatory_filetypes = ["biosample", "bioproject"]
    exist_sheet_list = ["BioProject"]
    ret = @excel2tsv.mandatory_sheet_check(mandatory_filetypes, exist_sheet_list, sheet_settings)
    assert_equal false, ret

    # ng case
    ## missng BioProject and BioSample sheets
    mandatory_filetypes = ["biosample", "bioproject"]
    exist_sheet_list = ["HELP"]
    ret = @excel2tsv.mandatory_sheet_check(mandatory_filetypes, exist_sheet_list, sheet_settings)
    assert_equal false, ret
  end
end