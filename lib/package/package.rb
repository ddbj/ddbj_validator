require 'rubygems'
require 'json'
require 'erb'
require 'logger'
require File.dirname(__FILE__) + "/../validator/common/sparql_base.rb"
require File.dirname(__FILE__) + "/../validator/common/common_utils.rb"

class Package < SPARQLBase

  #
  # Initializer
  #
  # ==== Args
  # endpoint: endpoint url
  #
  def initialize (endpoint)
    super(endpoint)
    @template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql")
    config_file_dir = File.absolute_path(File.dirname(__FILE__) + "/../../conf")
    @setting = YAML.load(ERB.new(File.read(config_file_dir + "/validator.yml")).result)
    @log_file = @setting["api_log"]["path"] + "/validator.log"
    @log = Logger.new(@log_file)
  end

  def output_log(ex)
    @log.error(ex.message)
    trace = ex.backtrace.map {|row| row}.join("\n")
    @log.error(trace)
  end

  def package_list (version)
    begin
      params = {version: version}
      if version.start_with?("1.2")
        sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/package_list_1.2.rq", params)
      else
        sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/package_list_1.4.rq", params)
      end
      ret = query(sparql_query)
      if ret.size > 0
        {status: "success", data: ret}
      else  # 結果が空の場合に存在するversionかチェック
        sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/is_exist_package_version.rq", params)
        ret_package_data = query(sparql_query)
        if ret_package_data.size == 0
          {status: "fail", message: "Wrong parameter: invalid package version"}
        else
          {status: "error", message: "Processing finished with error. Please check the validation service."}
        end
      end
    rescue => ex
      output_log(ex)
      {status: "error", message: "Processing finished with error. Please check the validation service."}
    end
  end

  # package_groupとpackageのリストをアプリ表示用に階層型に整形して返す
  def package_and_group_list (version)
    begin
      params = {version: version}
      begin
        if version.split(".")[0..1].join(".").to_f < 1.4
          return {status: "fail", message: "Wrong parameter: This method is supported since version 1.4."}
        end
      rescue
        return {status: "fail", message: "Wrong parameter: invalid package version."}
      end

      # package listを取得
      sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/package_list_1.4.rq", params)
      package_list = query(sparql_query)
      package_list.each do |row|
        row[:type] = "package"
      end

      # package group listを取得
      sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/package_group_list_1.4.rq", params)
      package_group_list = query(sparql_query)
      package_group_list.each do |row|
        row[:type] = "package_group"
      end

      # mergeして階層型に整形
      package_list.concat(package_group_list)
      if package_list.size > 0
        package_tree = []
        package_list.each_with_index do |package_info, idx|
          package_tree = add_package_tree(package_info, package_list, package_tree)
        end
        {status: "success", data: package_tree}
      else # 結果が空の場合に存在するversionかチェック
        sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/is_exist_package_version.rq", params)
        ret_package_data = query(sparql_query)
        if ret_package_data.size == 0
          {status: "fail", message: "Wrong parameter: invalid package version."}
        else
          {status: "error", message: "Processing finished with error. Please check the validation service."}
        end
      end
    rescue => ex
      output_log(ex)
      {status: "error", message: "Processing finished with error. Please check the validation service."}
    end
  end

  # treeの中から再帰的にpackage_groupを探す。ヒットすればそのpackage_groupを返し、なければnilを返す
  def find_package_group(tree, group_info)
    return nil if group_info[:type] != "package_group"
    hit_group = tree.find{|row| row[:package_group_name] == group_info[:package_group_name]}
    if hit_group.nil?
      tree.each do |package| #下の階層から検索
        unless package[:package_list].nil? || package[:package_list] == []
          return find_package_group(package[:package_list], group_info) unless find_package_group(package[:package_list], group_info).nil?
        end
      end
      return nil #下の階層にもなければnil
    else
      hit_group
    end
  end

  def add_package_tree(package_info, package_list, tree)
    # 初回に出てきたpackage_groupにlistを追加
    if find_package_group(tree, package_info).nil? && package_info[:type] == "package_group"
      package_info[:package_list] = []
    end

    # 親groupの記載がない(最上位)
    if package_info[:parent_package_group_uri].nil? || package_info[:parent_package_group_uri] == "" # find_package_group(tree, package_info).nil?
      if find_package_group(tree, package_info).nil?
        tree.push(package_info)
      end
      return tree
    end

    # 親を検索
    parent = package_list.find{|row| row[:type] == "package_group" && row[:package_group_uri] == package_info[:parent_package_group_uri]}
    unless parent.nil?
      if find_package_group(tree, parent).nil? #まだ追加されていなければ
        tree = add_package_tree(parent, package_list, tree) #親を追加
      end
      parent_group = find_package_group(tree, parent)
      parent_group[:package_list].push(package_info) if find_package_group(tree, package_info).nil?  #まだ追加されていなければ
    end
    tree
  end

  def attribute_list (version, package_id)
    begin
      params = {version: version, package_id: package_id}
      if version.start_with?("1.2")
        sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/attribute_list_1.2.rq", params)
      else
        sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/attribute_list_1.4.rq", params)
      end
      attr_list = query(sparql_query)
      if attr_list.size > 0
        if version.start_with?("1.4")
          sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/attribute_group_list_1.4.rq", params)
          group_list = query(sparql_query)
          attr_list.each do |row|
            match = group_list.find{|group| group[:attribute_name] == row[:attribute_name]}
            unless match.nil?
              row[:require_type] = "has_either_one_mandatory_attribute"
              row[:group_name] = match[:group_name]
            else
              row[:group_name] = ""
            end
          end
        end
        {status: "success", data: attr_list}
      else # 結果が空の場合に存在するversionかチェック
        sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/is_exist_package_version.rq", params)
        ret_package_data = query(sparql_query)
        if ret_package_data.size == 0
          {status: "fail", message: "Wrong parameter: invalid package version."}
        else
          {status: "fail", message: "Wrong parameter: invalid package version or package id."}
        end
      end
    rescue => ex
      output_log(ex)
      {status: "error", message: "Processing finished with error. Please check the validation service."}
    end
  end

  def attribute_template_file (version, package_id, only_biosample_sheet, accept_heder)
    begin
      params = {version: version, package_id: package_id}
      unless version.start_with?("1.4")
        return {status: "fail", message: "Invalid package version. Expected version is 1.4x"}
      end

      # accept header から希望ファイル形式を決める
      unless accept_heder.nil? || accept_heder["HTTP_ACCEPT"].nil?
        accept_heder_list = accept_heder["HTTP_ACCEPT"].split(",").map {|item| item.chomp.strip}
      end
      return_file_format = "excel" # default format
      if accept_heder_list.include?("text/tab-separated-values")
        return_file_format = "tsv"
      end
      template_file_dir = File.absolute_path(File.dirname(__FILE__) + "/../../public/template")
      puts template_file_dir
      file_path = ""
      if return_file_format == "tsv"
        file_path = "#{template_file_dir}/#{version}/bs/tsv/#{package_id}.tsv"
      else
        if only_biosample_sheet == true # BioSampleシートのみ
          file_path = "#{template_file_dir}/#{version}/bs/excel/#{package_id}.xlsx"
        else
          file_path = "#{template_file_dir}/#{version}/bpbs/excel/#{package_id}.xlsx"
        end
      end
      if File.exist?(file_path)
        return {status: "success", file_path: file_path, file_type: return_file_format}
      else
        puts "Not exist package template file: #{file_path}"
        return {status: "fail", message: "Invalid package_id"}
      end
    rescue => ex
      output_log(ex)
      {status: "error", message: "Attribute templete file processing finished with error. Please check the validation service."}
    end
  end

  def package_info (version, package_id)
    begin
      params = {version: version, package_id: package_id}
      if version.start_with?("1.2")
        sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/package_info_1.2.rq", params)
      else
        sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/package_info_1.4.rq", params)
      end
      ret = query(sparql_query)
      if ret.size > 0
        {status: "success", data: ret.first}
      else  # 結果が空の場合に存在するversionかチェック
        sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/is_exist_package_version.rq", params)
        ret_package_data = query(sparql_query)
        if ret_package_data.size == 0
          {status: "fail", message: "Wrong parameter: invalid package version."}
        else
          {status: "fail", message: "Wrong parameter: invalid package version or package id."}
        end
      end
    rescue => ex
      output_log(ex)
      {status: "error", message: "Processing finished with error. Please check the validation service."}
    end
  end

  private :find_package_group
  private :add_package_tree
end