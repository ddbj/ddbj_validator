require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'geocoder'
require 'date'
require 'net/http'
require 'roo'
require 'sanitize'
require File.dirname(__FILE__) + "/base.rb"
require File.dirname(__FILE__) + "/common/common_utils.rb"
require File.dirname(__FILE__) + "/common/date_format.rb"
require File.dirname(__FILE__) + "/common/ddbj_db_validator.rb"
require File.dirname(__FILE__) + "/common/organism_validator.rb"
require File.dirname(__FILE__) + "/common/sparql_base.rb"
require File.dirname(__FILE__) + "/common/validator_cache.rb"
require File.dirname(__FILE__) + "/common/xml_convertor.rb"

#
# A class for JVar validation
#
class JVarValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super()
    config_file_dir = File.absolute_path(File.dirname(__FILE__) + "/../../conf/jvar")
    xlsx_error_log = File.absolute_path(@conf[:log_dir] + "/excel_error.log")

    @log = Logger.new(xlsx_error_log)
    @conf[:validation_config] = JSON.parse(File.read(config_file_dir + "/rule_config_jvar.json"))
    @conf[:sheet_list] = JSON.parse(File.read(config_file_dir + "/sheet_list.json"))

    @error_list = error_list = []
    @validation_config = @conf[:validation_config] #need?
  end

  #
  # Validate the all rules for the jvar data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # data_xlsx: Excel file path
  #
  #
  def validate(data_xlsx, submitter_id=nil)
    @data_file = File::basename(data_xlsx)
    # excelファイルのロード
    xlsx = load_excel("JV_R0001", data_xlsx)
    return if xlsx.nil?
    jvar_data = xlsx2obj(xlsx) #パース

    # JSONファイル出力
    output_dir = File::dirname(data_xlsx)
    json_file_name = @data_file.split(".")[0..-2].join(".") + ".json"
    File.open("#{output_dir}/#{json_file_name}", "w") do |out|
      out.puts JSON.pretty_generate(jvar_data)
    end

    # TODO BioSample Validator実施
    # TODO BioProject Validator実施
  end

  #
  # rule:JV_R0001
  # Load an Excel file placed in the specified path using the roo library.
  # Returns an Roo::Excel object if the load succeeds, nil if it fails.
  #
  # ==== Args
  # data_xlsx: Excel file path
  # ==== Return
  # Roo::Excel object
  #
  def load_excel(rule_code, data_xlsx)
    xlsx = nil
    begin
      # 結合セルは対象セルの全てに同じ値を埋めるモード
      xlsx = Roo::Excelx.new(data_xlsx, {:expand_merged_ranges => true})
    rescue => ex
      annotation = [
        {key: "Excel file", value: @data_file},
        {key: "Error message", value: ex.message}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      message = "Failed to load the Excel file.: Please check the files: '#{data_xlsx}'.\n"
      message += "#{ex.message} (#{ex.class})"
      @log.warn("An Excel(Roo::Excelx) loading error has occurred.")
      output_exception_log(ex, message)
    end
    xlsx
  end

  #
  # Parses Excel data and returns an object with a defined schema.
  #
  # ==== Args
  # xlsx: Roo::Excel object
  # ==== Return
  # jvar_data
  #
  def xlsx2obj(xlsx)
    jvar_data = {}
    @conf[:sheet_list].each do |conf|
      sheet_name = ""
      if conf["sheet_name"]== "VARIANT CALL" || conf["sheet_name"] == "VARIANT REGION" # TODO 現状は無視する
        jvar_data[conf["json_key"]] = []
        next
      end
      hit = xlsx.sheets.select {|sheet| sheet.strip.downcase.gsub(" ", "") == conf["sheet_name"].strip.downcase.gsub(" ", "") } # allow case-insensitive and white space
      if hit.size == 1
        sheet_name = hit[0]
      elsif hit.size > 1
        hit = xlsx.sheets.select {|sheet| sheet.downcase == conf["sheet_name"].downcase } # allow case-insensitive
        sheet_name = hit[0] if hit.size >= 1
      end
      if sheet_name == ""
        #TODO 存在必須シートではエラーを出す。ここか？(OWL定義が来てから)
        jvar_data[conf["json_key"]] = []
      else
        sheet = load_sheet("JV_R0002", xlsx, sheet_name)
        jvar_data[conf["json_key"]] = parse_sheet_data(sheet_name, sheet)
      end
    end
    jvar_data
  end

  #
  # rule:JV_R0002
  # Load the specified Sheet in Excel and returns a Roo::Excel sheet object.
  #
  # ==== Args
  # xlsx: Roo::Excel object
  # sheet_name: sheet name of Excel file
  # ==== Return
  # Roo::Excel sheet object
  #
  def load_sheet(rule_code, xlsx, sheet_name)
    sheet = nil
    begin
      sheet = xlsx.sheet(sheet_name)
    rescue => ex
      annotation = [
        {key: "Excel file", value: @data_file},
        {key: "Sheet name", value: sheet_name},
        {key: "Error message", value: ex.message}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      message = "Failed to load the Excel file.: Please check the files: '#{@data_file}'.\n"
      message += "#{ex.message} (#{ex.class})"
      @log.warn("An Excel(Roo::Excelx) sheet loading error has occurred.")
      output_exception_log(ex, message)
    end
    sheet
  end

  #
  # Load the specified Sheet in Excel and returns a Roo::Excel sheet object.
  #
  # ==== Args
  # sheet_name: sheet name of Excel file
  # sheet: Roo::Excel sheet object
  # ==== Return
  # object corresponding to a single sheet
  #
  def parse_sheet_data(sheet_name, sheet)
    header = nil
    data_list = []
    (1..sheet.last_row).each do |row_num| # 行ごとにパース
      row = sheet.row(row_num)
      if row.first =~ /^\*/ # comment line
        # ignore
      elsif row.first =~ /^#/ # header
        if duplicated_header_line("JV_R0005", sheet_name, header, row_num) # 既にheader行が出現しているか
          header = parse_header_line(row)
        end
      else # data line
        # TODO method名が紛らわしい
        if data_line_before_header_line("JV_R0004", sheet_name, header, row_num) # headerより前に出現していない
          if ignore_blank_line("JV_R0007", sheet_name, row, row_num) # 空白行では無い
            row_data = parse_data_row(sheet_name, header, row, row_num)
            data_list.push(row_data)
          end
        end
      end
    end
    exist_header_line("JV_R0003", sheet_name, header) # not found header line?
    data_list
  end

  #
  # Parse header line.
  #
  # ==== Args
  # row: Roo::Excel row object
  # ==== Return
  # header_index_list: {0: "#STUDY", 1:	"study_id" ...}
  def parse_header_line(row)
    header = {}
    row.each_with_index do |cell, idx|
      next if cell.nil?
      header[idx] = cell_value(cell)
    end
    header
  end

  #
  # Parse one data line.
  #
  # ==== Args
  # row: Roo::Excel row object
  # ==== Return
  # row object:
  # { annotations: [ {name: "study_id", value: "Mishima2020"}, {name: "study_description", value: "xxxxx"}, ... ] }
  #
  def parse_data_row(sheet_name, header,row, row_num)
    row_data = {}
    annotations = []
    row.each_with_index do |cell, column_num|
      if cell_value_with_no_header("JV_R0006", sheet_name, header, row_num, cell, column_num)
        annotations.push({name: header[column_num], value: cell_value(cell)})
      end
    end
    row_data[:annotations] = annotations
    row_data
  end

  #
  # rule:JV_R0003
  # If the header information is empty, add error information.
  #
  def exist_header_line(rule_code, sheet_name, header)
    ret = true
    if header.nil? || header == {}
      ret = false
      annotation = [
        {key: "Excel file", value: @data_file},
        {key: "Sheet name", value: sheet_name}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # rule:JV_R0004
  # If the header information is empty, add error information.
  #
  def data_line_before_header_line(rule_code, sheet_name, header, row_num)
    ret = true
    if header.nil? || header == {}
      ret = false
      annotation = [
        {key: "Excel file", value: @data_file},
        {key: "Sheet name", value: sheet_name},
        {key: "line number", value: row_num}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # rule:JV_R0005
  # Check if a header line has already been set (duplication of header lines).
  #
  def duplicated_header_line(rule_code, sheet_name, header, row_num)
    ret = true
    if !(header.nil? || header == {})
      ret = false
      annotation = [
        {key: "Excel file", value: @data_file},
        {key: "Sheet name", value: sheet_name},
        {key: "line number", value: row_num}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # rule:JV_R0006
  # Check for values in lines with no header.
  #
  def cell_value_with_no_header(rule_code, sheet_name, header, row_num, cell, column_num)
    ret = true
    if header[column_num].nil? || header[column_num] == "" || header[column_num].start_with?("#")
      ret = false
      unless cell.nil? # ヘッダーがない列に値がある
        cell_pos = "#{Roo::Utils.number_to_letter(column_num + 1)}#{row_num.to_s}"
        annotation = [
          {key: "Excel file", value: @data_file},
          {key: "Sheet name", value: sheet_name},
          {key: "Cell", value: cell_pos},
          {key: "Value", value: cell_value(cell)}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
    end
    ret
  end

  #
  # rule:JV_R0007
  # If it is an empty line, add warnning information.
  #
  def ignore_blank_line(rule_code, sheet_name, row, row_num)
    ret = true
    if row.uniq == [nil]
      ret = false
      annotation = [
        {key: "Excel file", value: @data_file},
        {key: "Sheet name", value: sheet_name},
        {key: "line number", value: row_num}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    ret
  end

  #
  # Returns a string representation of the cell value.
  #
  def cell_value(cell)
    value = nil
    if cell.nil?
      value = ""
    elsif cell.to_s.start_with?("<html")
      value = html2text(cell.to_s)
    #elseif
     #TODO date型をどうするか？そのまま？
    else
      value = cell.to_s # all
    end
    value
  end

  #
  # Returns a string extracted from HTML format.
  #
  # ==== Args
  # html_text: "<html>#biosample<b>_accession</b></html>"
  # ==== Return
  # text: "#biosample_accession"
  #
  def html2text(html)
    Sanitize.clean(html, :whitespace_elementces => [:p, :div] )
  end

end