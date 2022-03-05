require 'roo'
require 'csv'
require 'fileutils'
require File.dirname(__FILE__) + "/common_utils.rb"

#
# A class for convert from excel sheet to tsv files
#
class Excel2Tsv
  # filetypeとExcelのシートの関係
  @@sheet_settings = {
    "bioproject" => "BioProject",
    "biosample" => "BioSample",
    "metabobank_idf" => "Study (IDF)",
    "metabobank_sdrf" => "Assay (SDRF)"
  }

  def initialize
    rule_path = File.absolute_path(File.dirname(__FILE__) + "/../../../conf/all_db/rule_config_all_db.json")
    @validation_config = JSON.parse(File.read(rule_path))
    @error_list = []
  end

  #
  # Excelファイルをパースして、規定のシートをTSVファイルに変換して出力する.
  # 成功した場合は、filetypeと保存TSVファイルのパスを返す.
  # エラーが発生した場合にはエラーリストを返す.
  #
  # ==== Args
  # original_excel_path: パースするExcelファイルのパス
  # base_dir: TSVファイルを出力するベースのディレクトリ. TSVはfiletypeに応じて保管される #{base_dir}/biosample/xxxxx.tsv
  # mandatory_sheets: 指定された
  # ==== Return
  # {status: "succeed", filetypes: {bioproject: bioproject_tsv_path, biosample: biosample_tsv_path}}
  # {status: "failed", error_list: [xxx]}
  #
  def split_sheet(original_excel_path, base_dir, mandatory_sheets=[])
    ret = {}
    sheet_list = nil
    begin
      @data_file = File::basename(original_excel_path)
      xlsx = Roo::Excelx.new(original_excel_path, {:expand_merged_ranges => true})
      sheet_list = xlsx.sheets
    rescue => ex
      # load error
      annotation = [
        {key: "Message", value: "Failed read excel file."},
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + "ALL_R0001"],  @data_file, annotation)
      ret[:status] = "failed"
      ret[:error_list] = [error_hash]
      return ret
    end

    # 必須シートが存在しているかのチェック
    unless mandatory_sheets == [] # 必須チェックの指定がない場合はOK
      unless mandatory_sheet_check(mandatory_sheets, sheet_list, @@sheet_settings) == true
        ret[:status] = "failed"
        ret[:error_list] = @error_list
        return ret
      end
    end

    filetypes = {}
    @@sheet_settings.each do |filetype, sheet_name|
      if sheet_list.include?(sheet_name)
        sheet = nil
        begin
          sheet = xlsx.sheet(sheet_name)
          # 出力先ファイルの決定
          output_file_dir = "#{base_dir}/#{filetype}"
          output_file_name = "#{File.basename(original_excel_path, ".xlsx")}_#{filetype}.tsv"
          FileUtils.mkdir_p(output_file_dir) unless File.exist?(output_file_dir)
          output_file_path = "#{output_file_dir}/#{output_file_name}"
          # TSVを出力
          CSV.open(output_file_path, "w", col_sep: "\t") do |tsv|
            (1..sheet.last_row).each do |row_num|
              row = sheet.row(row_num)
              tsv << row
            end
          end
          filetypes[filetype.to_sym] = output_file_path # シートが読めたらValidation対象としてfiletypeと変換したTSVを追加する
        rescue
          annotation = [
            {key: "Message", value: "Failed parse sheet in Excel file."},
            {key: "Sheet name", value: sheet.to_s}
          ]
          error_hash = CommonUtils::error_obj(@validation_config["rule" + "ALL_R0001"], @data_file, annotation)
          ret[:status] = "failed"
          ret[:error_list] = [error_hash]
          return ret
        end
      end
    end
    ret[:status] = "succeed"
    ret[:filetypes] = filetypes
    ret
  end

  #
  # 必須チェックするfiletypeのシートが存在するかのチェック.
  # 指定された
  #
  # ==== Args
  # mandatory_filetypes: チェックするfiletypeのリスト e.g. ["bioproject", "biosample"]
  # exist_sheet_list: Excelにあったシート名のリスト e.g.["BioProject", "BioSample"]
  # ==== Return
  # true/false
  #
  def mandatory_sheet_check(mandatory_filetypes, exist_sheet_list, sheet_settings)
    ret = true
    # filetypeに対応するシート名を取得
    mandatory_sheet_list = []
    mandatory_filetypes.each do |sheet_filetype|
      unless sheet_settings[sheet_filetype].nil?
        mandatory_sheet_list.push(sheet_settings[sheet_filetype])
      end
    end
    # 不足シートのリスト
    missing_sheet_list = mandatory_sheet_list - exist_sheet_list
    if missing_sheet_list.size > 0
      ret = false
      annotation = [
        {key: "Mandatory sheet names", value: mandatory_sheet_list.to_s},
        {key: "Missing sheet names", value: missing_sheet_list.to_s}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + "ALL_R0002"],  @data_file, annotation)
      @error_list.push(error_hash)
    end
    ret
  end
end