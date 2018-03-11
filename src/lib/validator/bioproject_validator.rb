require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'geocoder'
require 'date'
require 'net/http'
require 'nokogiri'
require File.dirname(__FILE__) + "/base.rb"
require File.dirname(__FILE__) + "/common/common_utils.rb"
require File.dirname(__FILE__) + "/common/ddbj_db_validator.rb"
require File.dirname(__FILE__) + "/common/organism_validator.rb"

#
# A class for BioProject validation
#
class BioProjectValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super
    @conf.merge!(read_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf/bioproject")))
    CommonUtils::set_config(@conf)

    @error_list = error_list = []

    @validation_config = @conf[:validation_config] #need?
    @org_validator = OrganismValidator.new(@conf[:sparql_config]["master_endpoint"], @conf[:sparql_config]["slave_endpoint"])
    @db_validator = DDBJDbValidator.new(@conf[:ddbj_db_config])
  end


  #
  # 各種設定ファイルの読み込み
  #
  # ==== Args
  # config_file_dir: 設定ファイル設置ディレクトリ
  #
  #
  def read_config (config_file_dir)
    config = {}
    begin
      config[:validation_config] = JSON.parse(File.read(config_file_dir + "/rule_config_bioproject.json")) #TODO auto update when genereted
      config[:xsd_path] = File.absolute_path(config_file_dir + "/xsd/Package.xsd")
      config
    rescue => ex
      message = "Failed to parse the setting file. Please check the config file below.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
  end

  #
  # Validate the all rules for the bioproject data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # data_xml: xml file path
  #
  #
  def validate (data_xml, submitter_id=nil)
    valid_xml = not_well_format_xml("BP_R0001", data_xml)
    return unless valid_xml
    # xml検証が通った場合のみ実行
    @data_file = File::basename(data_xml)
    valid_schema = xml_data_schema("BP_R0002", data_xml, @conf[:xsd_path])
    doc = Nokogiri::XML(File.read(data_xml))
    project_set = doc.xpath("//PackageSet/Package/Project")

    if submitter_id.nil?
      @submitter_id = @xml_convertor.get_bioproject_submitter_id(xml_document)
    else
      @submitter_id = submitter_id
    end
    #TODO @submitter_id が取得できない場合はエラーにする?

    #submission_idは任意。Dway経由、DB登録済みデータを取得した場合にのみ取得できることを想定
    @submission_id = @xml_convertor.get_bioproject_submission_id(xml_document)

    multiple_projects("BP_R0037", project_set)
    project_name_list = @db_validator.get_bioproject_names(@submitter_id)
    project_title_desc_list = @db_validator.get_bioproject_title_descs(@submitter_id)
    #各プロジェクト毎の検証
    project_set.each_with_index do |project_node, idx|
      idx += 1
      project_name = get_bioporject_label(project_node, idx)
      duplicated_project_name("BP_R0003", project_name, project_node, project_name_list, @submission_id, idx)
      identical_project_title_and_description("BP_R0005", project_name, project_node, idx)
      short_project_description("BP_R0006", project_name, project_node, idx)
      empty_description_for_other_relevance("BP_R0007", project_name, project_node, idx)
      empty_description_for_other_subtype("BP_R0008", project_name, project_node, idx)
      empty_target_description_for_other_sample_scope("BP_R0009", project_name, project_node, idx)
      empty_target_description_for_other_material("BP_R0010", project_name, project_node, idx)
      empty_target_description_for_other_capture("BP_R0011", project_name, project_node, idx)
      empty_method_description_for_other_method_type("BP_R0012", project_name, project_node, idx)
      empty_data_description_for_other_data_type("BP_R0013", project_name, project_node, idx)
      invalid_publication_identifier("BP_R0014", project_name, project_node, idx)
      empty_publication_reference("BP_R0015", project_name, project_node, idx)
      missing_strain_isolate_cultivar("BP_R0017", project_name, project_node, idx)
      taxonomy_at_species_or_infraspecific_rank("BP_R0018", project_name, project_node, idx)
      empty_organism_description_for_multi_species("BP_R0019", project_name, project_node, idx)
      metagenome_or_environmental("BP_R0020", project_name, project_node, idx)
      invalid_locus_tag_prefix("BP_R0021", project_name, project_node, idx)
      invalid_biosample_accession("BP_R0022", project_name, project_node, idx)
      missing_project_name("BP_R0036", project_name, project_node, idx)
      taxonomy_error_warning("BP_R0038", project_name, project_node, idx)
      taxonomy_name_and_id_not_match("BP_R0039", project_name, project_node, idx)
      invalid_project_type("BP_R0040", project_name, project_node, idx)
    end

    link_set = doc.xpath("//PackageSet/Package/ProjectLinks")
    #各リンク毎の検証
    link_set.each_with_index do |link_node, idx|
      invalid_umbrella_project("BP_R0016", "Link", link_node, idx)
    end
  end

  #
  # Projectを一意識別するためのlabelを返す
  # Project Name, Project Title, Accession IDの順に採用される
  # いずれもない場合には何番目のprojectかを示すためラベルを返す(例:"1st project")
  #
  # ==== Args
  # project_node: 1projectのxml nodeset オプジェクト
  # line_num
  #
  def get_bioporject_label (project_node, line_num)
    project_name = ""
    #Project Name
    name_node = project_node.xpath("Project/ProjectDescr/Name")
    if !name_node.empty? && name_node.text.strip != ""
      project_name = name_node.text
    elsif
      #Project Title
      title_node = project_node.xpath("Project/ProjectDescr/Title")
      if !title_node.empty? && title_node.text.strip != ""
        project_name = title_node.text
      elsif
        #Accession ID
        archive_node = project_node.xpath("Project/ProjectID/ArchiveID[@accession]")
        if !archive_node.empty? && archive_node.attr("accession").text.strip != ""
          project_name = archive_node.attr("accession").text
        end
      end
    end
    # いずれの記述もない場合には何番目のprojectであるかを示す
    if project_name == ""
      ordinal_num = ""
      if line_num == 11
        ordinal_num = "11th"
      elsif line_num.to_s[-1] == "1"
        ordinal_num = line_num.to_s + "st"
      elsif line_num.to_s[-1] == "2"
        ordinal_num = line_num.to_s + "nd"
      elsif line_num.to_s[-1] == "3"
        ordinal_num = line_num.to_s + "rd"
      else
        ordinal_num = line_num.to_s + "th"
      end
      project_name = ordinal_num + " project"
    end
    project_name
  end

### validate method ###

  #
  # rule:BP_R0003
  # project name がアカウント単位でユニークではない
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # project_name_list: submitter_idに紐付くプロジェクトのproject_nameの一覧
  # ==== Return
  # true/false
  #
  def duplicated_project_name (rule_code, project_label, project_node, project_name_list, submission_id, line_num)
    result = true
    name_path = "//Project/ProjectDescr/Name"

    if !project_node.xpath(name_path).empty? #要素あり
      project_name = get_node_text(project_node, name_path)
      # submission_idがなければDBから取得したデータではないため、DB内に一つでも同じproject nameがあるとNG
      result = false if submission_id.nil? && project_name_list.count(project_name) >= 1
      # submission_idがあればDBから取得したデータであり、DB内に同一データが1つある。2つ以上あるとNG
      result = false if !submission_id.nil? && project_name_list.count(project_name) >= 2

      if result == false
        annotation = [
            {key: "Project name", value: project_label},
            {key: "Project name", value: project_name},
            {key: "Path", value: [name_path]},
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
    end
    result
  end

  #
  # rule:BP_R0004
  # project title & description がアカウント単位でユニークではない
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # project_title_desc_list: submitter_idに紐付くプロジェクトのtitle,descriptionの一覧
  # ==== Return
  # true/false
  #
  def duplicated_project_title_and_description (rule_code, project_label, project_node, project_title_desc_list, submission_id, line_num)
    result = true
    title_path = "//Project/ProjectDescr/Title"
    desc_path = "//Project/ProjectDescr/Description"

    title = description = ""
    if !project_node.xpath(title_path).empty? #要素あり
      title = get_node_text(project_node, title_path)
    end
    if !project_node.xpath(desc_path).empty? #要素あり
      description = get_node_text(project_node, desc_path)
    end
    combination_text = [title, description].join(",")
    # submission_idがなければDBから取得したデータではないため、DB内に一つでも同じtitle&descがあるとNG
    result = false if submission_id.nil? && project_title_desc_list.count(combination_text) >= 1
    # submission_idがあればDBから取得したデータであり、DB内に同一データが1つある。2つ以上あるとNG
    result = false if !submission_id.nil? && project_title_desc_list.count(combination_text) >= 2

    if result == false
      annotation = [
        {key: "Project name", value: project_label},
        {key: "Title", value: title},
        {key: "Description", value: description},
        {key: "Path", value: [title_path, desc_path]},
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
    end
    result
  end

  #
  # rule:BP_R0005
  # プロジェクトの description と title が完全一致でエラー
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def identical_project_title_and_description (rule_code, project_label, project_node, line_num)
    result = true
    title_path = "//Project/ProjectDescr/Title"
    desc_path = "//Project/ProjectDescr/Description"
    if !project_node.xpath(title_path).empty? && !project_node.xpath(desc_path).empty? #両方要素あり
      title = get_node_text(project_node, title_path)
      description = get_node_text(project_node, desc_path)
      if title == description
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Title", value: title},
          {key: "Description", value: description},
          {key: "Path", value: [title_path, desc_path]},
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:BP_R0006
  # description が空白文字を除いて 100 文字以下でエラー
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def short_project_description (rule_code, project_label, project_node, line_num)
    result = true
    desc_path = "//Project/ProjectDescr/Description"
    if !project_node.xpath(desc_path).empty? #要素あり
      description = get_node_text(project_node, desc_path)
      if description.gsub(" ", "").size <= 100 #空白のぞいて100文字以下
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Description", value: description},
          {key: "Path", value: desc_path}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:BP_R0007
  # Relevance が Other のとき要素テキストとして説明が提供されていない
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def empty_description_for_other_relevance (rule_code, project_label, project_node, line_num)
    result = true
    other_path = "//Project/ProjectDescr/Relevance/Other"
    if !project_node.xpath(other_path).empty? #要素あり
      if node_blank?(project_node, other_path) #テキストなし
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Path", value: other_path}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:BP_R0008
  # ProjectTypeTopAdminのsubtype属性がeOtherのとき要素テキストとして説明が提供されているか
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def empty_description_for_other_subtype (rule_code, project_label, project_node, line_num)
    result = true
    other_path = "//Project/ProjectType/ProjectTypeTopAdmin[@subtype = 'eOther']"
    desc_other_path = "//Project/ProjectType/ProjectTypeTopAdmin/DescriptionSubtypeOther"
    if !project_node.xpath(other_path).empty? #eOther属性値を持つ要素あ
      if node_blank?(project_node, desc_other_path) #DescriptionSubtypeOtherなしor空
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Path", value: desc_other_path}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:BP_R0009
  # Targetのsample_scope属性がeOther のとき要素テキストとして説明が提供されていない場合エラー
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def empty_target_description_for_other_sample_scope (rule_code, project_label, project_node, line_num)
    result = true
    target_path = "//Project/ProjectType/ProjectTypeSubmission/Target[@sample_scope='eOther']"
    target_desc_path = "Project/ProjectType/ProjectTypeSubmission/Target/Description"
    if !project_node.xpath(target_path).empty? #eOther属性値を持つ要素あり
      if node_blank?(project_node, target_desc_path) #Descriptionなしor空
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Path", value: target_desc_path}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:BP_R0010
  # Targetのmaterial属性がeOther のとき要素テキストとして説明が提供されていない場合エラー
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def empty_target_description_for_other_material (rule_code, project_label, project_node, line_num)
    result = true
    target_path = "//Project/ProjectType/ProjectTypeSubmission/Target[@material='eOther']"
    target_desc_path = "Project/ProjectType/ProjectTypeSubmission/Target/Description"
    if !project_node.xpath(target_path).empty? #eOther属性値を持つ要素あり
      if node_blank?(project_node, target_desc_path) #Descriptionなしor空
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Path", value: target_desc_path}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:BP_R0011
  # Targetのcapture属性がeOther のとき要素テキストとして説明が提供されていない場合エラー
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def empty_target_description_for_other_capture (rule_code, project_label, project_node, line_num)
    result = true
    target_path = "//Project/ProjectType/ProjectTypeSubmission/Target[@capture='eOther']"
    target_desc_path = "Project/ProjectType/ProjectTypeSubmission/Target/Description"
    if !project_node.xpath(target_path).empty? #eOther属性値を持つ要素あり
      if node_blank?(project_node, target_desc_path) #Descriptionなしor空
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Path", value: target_desc_path}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:BP_R0012
  # Methodのmethod_type属性がeOther のとき要素テキストとして説明が提供されていない場合エラー
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def empty_method_description_for_other_method_type (rule_code, project_label, project_node, line_num)
    result = true
    method_path = "//Project/ProjectType/ProjectTypeSubmission/Method[@method_type='eOther']"
    if !project_node.xpath(method_path).empty? #eOther属性値を持つ要素あり
      if node_blank?(project_node, method_path) #Methodなしor空
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Path", value: method_path}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:BP_R0013
  # Objectives/Dataのdata_type属性がeOther のとき要素テキストとして説明が提供されていない場合エラー
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def empty_data_description_for_other_data_type (rule_code, project_label, project_node, line_num)
    result = true
    data_path = "//Project/ProjectType/ProjectTypeSubmission/Objectives/Data"
    project_node.xpath(data_path).each_with_index do |data_node, idx| #複数出現の可能性あり
      if !data_node.xpath("//Data[@data_type='eOther']").empty? #eOther属性値を持つ要素あり
        if node_blank?(data_node, ".") #Dataなしor空
          annotation = [
            {key: "Project name", value: project_label},
            {key: "Path", value: "#{data_path}[#{idx + 1}]"} #順番を表示
          ]
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
          result = false
        end
      end
    end
    result
  end

  #
  # rule:BP_R0014
  # DbTypeがePubmed/ePMCの場合に実在するidかどうか、eDOIはチェックしない
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def invalid_publication_identifier (rule_code, project_label, project_node, line_num)
    result = true
    pub_path = "//Project/ProjectDescr/Publication"
    project_node.xpath(pub_path).each_with_index do |pub_node, idx| #複数出現の可能性あり
      valid = true
      db_type = ""
      id =  get_node_text(pub_node,"@id")
      common = CommonUtils.new
      begin
        if !pub_node.xpath("DbType[text()='ePubmed']").empty? && !common.exist_pubmed_id?(id)
          result = valid = false
          db_type = "ePubmed"
        elsif !pub_node.xpath("DbType[text()='eDOI']").empty?
          # DOIの場合はチェックをしない  https://github.com/ddbj/ddbj_validator/issues/18
        elsif !pub_node.xpath("DbType[text()='ePMC']").empty?  && !common.exist_pmc_id?(id)
          result = valid = false
          db_type = "ePMC"
        end

        if (!valid)
          annotation = [
            {key: "Project name", value: project_label},
            {key: "DbType", value: db_type},
            {key: "ID", value: id},
            {key: "Path", value: "#{pub_path}[#{idx + 1}]/@id"} #順番を表示
          ]
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
          result = false
        end
      rescue => ex #NCBI問合せ中のシステムエラーの場合はその旨メッセージを追加
        annotation = [
          {key: "Project name", value: project_label},
          {key: "DbType", value: db_type},
          {key: "ID", value: id},
          {key: "Path", value: "#{pub_path}[#{idx + 1}]/@id"}, #順番を表示
          {key: "Message", value: "Validation processing failed because connection to NCBI service failed." }
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, false)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:BP_R0015
  # DbTypeがeNotAvailableのときReference要素で説明が提供されていない場合エラー
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def empty_publication_reference (rule_code, project_label, project_node, line_num)
    result = true
    pub_path = "//Project/ProjectDescr/Publication"
    project_node.xpath(pub_path).each_with_index do |pub_node, idx| #複数出現の可能性あり
      if !pub_node.xpath("DbType[text()='eNotAvailable']").empty? #eNotAvailable属性値を持つ要素あり
        if node_blank?(pub_node, "Reference") #Referenceなしor空 "//Reference"とは書かないこと
          annotation = [
            {key: "Project name", value: project_label},
            {key: "Path", value: "#{pub_path}[#{idx + 1}]/Reference"} #順番を表示
          ]
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
          result = false
        end
      end
    end
    result
  end

  #
  # rule:BP_R0016
  # 選択された Umbrella BioProject が実在しない、指定されている Umbrella が DDBJ DB に存在すれば OK
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def invalid_umbrella_project (rule_code, link_label, link_node, line_num)
    result = true
    hierar_path = "Link/Hierarchical[@type='TopAdmin']"
    link_node.xpath(hierar_path).each_with_index do |hierar_node, idx_h|
      member_path = "MemberID/@accession"
      hierar_node.xpath(member_path).each_with_index do |acs_attr_node, idx_m|
        unless node_blank?(acs_attr_node)
          bioproject_accession = get_node_text(acs_attr_node)
          is_umbrella = @db_validator.umbrella_project?(bioproject_accession)
          if !is_umbrella
            annotation = [
             {key: "Project name", value: "None"},
             {key: "BioProject accession", value: bioproject_accession},
             {key: "Path", value: "//Link/Hierarchical[#{idx_h + 1}]/#{member_path}[#{idx_m + 1}]"}
            ]
            error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
            @error_list.push(error_hash)
            result = false
          end
        end
      end
    end
    result
  end

  #
  # rule:BP_R0017
  # organism: sample scope = "mono-isolate" の場合は strain or breed or cultivar or isolate or label 必須
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def missing_strain_isolate_cultivar (rule_code, project_label, project_node, line_num)
    result = true
    sample_scope_attr = "//Target[@sample_scope='eMonoisolate']"
    monoisolate = project_node.xpath(sample_scope_attr)
    unless monoisolate.empty? #eMonoisolateである場合にチェック
      if ( node_blank?(project_node, "//Organism/Label") \
           && node_blank?(project_node, "//Organism/Strain") \
           && node_blank?(project_node, "//Organism/IsolateName") \
           && node_blank?(project_node, "//Organism/Breed") \
           && node_blank?(project_node, "//Organism/Cultivar"))
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Path", value: "//Organism/Label | //Organism/Strain | //Organism/IsolateName | //Organism/Breed | //Organism/Cultivar"}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:BP_R0018
  # organism: sample scope = "multi-species" 以外の場合、species レベル以下の taxonomy が必須 (multi-species の場合、任意で species レベル以上を許容)
  # biosample rule:4,45,96と関連
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def taxonomy_at_species_or_infraspecific_rank (rule_code, project_label, project_node, line_num)
    result = true
    # tax_idが記述されていればtax_idを使用し、なければorganism_nameからtax_idを取得する
    tax_id = nil
    taxid_path = "//Project/ProjectType/ProjectTypeSubmission/Target/Organism/@taxID"
    if !node_blank?(project_node, taxid_path) && get_node_text(project_node, taxid_path).chomp.strip != "1" #tax_id=1(root)は未指定として扱う
      tax_id = get_node_text(project_node, taxid_path).chomp.strip
    else
      orgname_path = "//Project/ProjectType/ProjectTypeSubmission/Target/Organism/OrganismName"
      unless node_blank?(project_node, orgname_path)
        organism_name = get_node_text(project_node, orgname_path).chomp.strip
        ret = @org_validator.suggest_taxid_from_name(organism_name)
        if ret[:status] == "exist"
          tax_id = ret[:tax_id]
        end
      end
    end
    unless tax_id.nil? #taxIDが確定できない場合はチェックしない
      multispecies = project_node.xpath("//Project/ProjectType/ProjectTypeSubmission/Target[@sample_scope='eMultispecies']")
      if multispecies.empty? #eMultispeciesではない場合にチェックする
        result = @org_validator.is_infraspecific_rank(tax_id)
        if result == false
          annotation = [
            {key: "Project name", value: project_label},
            {key: "Path", value: [taxid_path, orgname_path]}
          ]
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
          result = false
        end
      end
    end
    result
  end

  #
  # rule:BP_R0019
  # organism: sample scope = "multi-species" の場合 Target > Description が必須、要素があり、内容が空の場合にエラー
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def empty_organism_description_for_multi_species (rule_code, project_label, project_node, line_num)
    result = true
    sample_scope_attr = "//Target[@sample_scope='eMultispecies']"
    multispecies = project_node.xpath(sample_scope_attr)
    unless multispecies.empty? #eMultispeciesである場合にチェック
      node_path = "//Target/Description"
      if node_blank?(project_node, node_path)
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Path", value: node_path}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:BP_R0020
  # organism: sample scope = "environment" の場合は biosample と同様にmetagenome などのチェック
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def metagenome_or_environmental (rule_code, project_label, project_node, line_num)
    result = true
    # tax_idが記述されていればtax_idを使用し、なければorganism_nameからtax_idを取得する
    # TODO rule18と同じコードまとめたい
    tax_id = nil
    taxid_path = "//Project/ProjectType/ProjectTypeSubmission/Target/Organism/@taxID"
    if !node_blank?(project_node, taxid_path) && get_node_text(project_node, taxid_path).chomp.strip != "1" #tax_id=1(root)は未指定として扱う
      tax_id = get_node_text(project_node, taxid_path).chomp.strip
    else
     orgname_path = "//Project/ProjectType/ProjectTypeSubmission/Target/Organism/OrganismName"
      unless node_blank?(project_node, orgname_path)
        organism_name = get_node_text(project_node, orgname_path).chomp.strip
        ret = @org_validator.suggest_taxid_from_name(organism_name)
        if ret[:status] == "exist"
          tax_id = ret[:tax_id]
        end
      end
    end
    unless tax_id.nil? #taxIDが確定できない場合はチェックしない
      environment = project_node.xpath("//Project/ProjectType/ProjectTypeSubmission/Target[@sample_scope='eEnvironment']")
      unless environment.empty? #eEnvironmentである場合にチェック
        #tax_id がmetagenome配下かどうか
        linages = [OrganismValidator::TAX_UNCLASSIFIED_SEQUENCES]
        db_org_name = @org_validator.get_organism_name(tax_id)
        unless @org_validator.has_linage(tax_id, linages) && !db_org_name.nil? && db_org_name.end_with?("metagenome")
          annotation = [
            {key: "Project name", value: project_label},
            {key: "Path", value: [taxid_path, orgname_path]}
          ]
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
          result = false
        end
      end
    end
    result
  end

  #
  # rule:BP_R0021
  # LocusTagPrefix要素の記述がある場合にbiosample_id属性とLocusTagPrefixのテキストが正しい組合せで記述されているかチェック
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def invalid_locus_tag_prefix (rule_code, project_label, project_node, line_num)
    result = true
    locus_tag_path = "//Project/ProjectDescr/LocusTagPrefix"
    project_node.xpath(locus_tag_path).each_with_index do |locus_tag_node, idx| #XSD定義では複数記述可能
      isvalid = true
      # locus_tagとbiosampleのどちらか指定が欠けているればエラー
      if (node_blank?(locus_tag_node, ".") || node_blank?(locus_tag_node, "@biosample_id"))
        isvalid = result = false #複数ノードの一つでもエラーがあればresultをfalseとする
      else
        # biosample_idからDB検索してlocus_tag_prefixが取得できない、値が異なる場合にエラー
        biosample_accession = get_node_text(locus_tag_node, "@biosample_id")
        locus_tag_prefix = get_node_text(locus_tag_node)
        bp_locus_tag_prefix =  @db_validator.get_biosample_locus_tag_prefix(biosample_accession)
        if bp_locus_tag_prefix.nil?
          isvalid = result = false
        else
          # get_biosample_locus_tag_prefixはハッシュの配列で返ってくる.findで検索して一つも合致しなければエラー
          if bp_locus_tag_prefix.find{|row| row["locus_tag_prefix"] == locus_tag_prefix}.nil?
            isvalid = result = false
          end
        end
      end
      if isvalid == false
        annotation = [
          {key: "Project name", value: project_label}
        ]
        if node_blank?(locus_tag_node, ".")
          annotation.push({key: "LocusTagPrefix", value: ""})
        else
          annotation.push({key: "LocusTagPrefix", value: locus_tag_node.xpath("text()").text})
        end
        if node_blank?(locus_tag_node, "@biosample_id")
          annotation.push({key: "biosample_id", value: ""})
        else
          annotation.push({key: "biosample_id", value: locus_tag_node.xpath("@biosample_id").text})
        end
        annotation.push({key: "Path", value: ["#{locus_tag_path}[#{idx + 1}]", "#{locus_tag_path}[#{idx + 1}]/@biosample_id"]})
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
    end
    result
  end

  #
  # rule:BP_R0022
  # LocusTagPrefix要素のbiosample_id属性の記述がある場合biosample_idはDDBJのIDであるかチェック
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def invalid_biosample_accession (rule_code, project_label, project_node, line_num)
    result = true
    biosample_id_path = "//Project/ProjectDescr/LocusTagPrefix/@biosample_id"
    project_node.xpath(biosample_id_path).each_with_index do |biosample_id_node, idx| #XSD定義では複数記述可能
      isvalid = true
      unless node_blank?(biosample_id_node, ".") #属性値がある
        biosample_accession = biosample_id_node.text
        if biosample_accession =~ /^SAMD\d{8}$/ || biosample_accession =~ /^SSUB\d{6}$/
          #DBにIDがあるか検証する
          unless @db_validator.is_valid_biosample_id?(biosample_accession)
            isvalid = result = false
          end
        else #formatエラー
          isvalid = result = false
        end
      end
      if isvalid == false
        annotation = [
          {key: "Project name", value: project_label},
          {key: "biosample_id", value: biosample_accession},
          {key: "Path", value: "#{biosample_id_path}[#{idx + 1}]"}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
    end
    result
  end

  #
  # rule:BP_R0036
  # 参照ラベルとしての project name 必須
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def missing_project_name (rule_code, project_label, project_node, line_num)
    result = true
    project_name_path = "//Project/ProjectDescr/Name"
    if node_blank?(project_node, project_name_path)
      annotation = [
        {key: "Project name", value: project_label},
        {key: "Path", value: "#{project_name_path}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:BP_R0037
  # 1 BioProject XML - 1 BioProject であるか
  #
  # ==== Args
  # project_set_node: a bioproject set node object
  # ==== Return
  # true/false
  #
  def multiple_projects (rule_code, project_set_node)
    result = true
    if project_set_node.size > 1
      annotation = [
        {key: "Number of <Project>", value: "#{project_set_node.size}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:BP_R0038
  # 指定されたtaxonomy_idに対して生物種名が適切であるかの検証
  # Taxonomy ontologyのScientific nameとの比較を行う
  # 一致しなかった場合にはtaxonomy_idを元にorganismの自動補正情報をエラーリストに出力する
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def taxonomy_name_and_id_not_match (rule_code, project_label, project_node, line_num)
    result = true
    taxid_path = "//Organism/@taxID"
    orgname_path = "//Organism/OrganismName"
    if !project_node.xpath(orgname_path).empty? && !node_blank?(project_node, taxid_path) #両方要素あり
      organism_name = get_node_text(project_node, orgname_path)
      taxonomy_id = get_node_text(project_node, taxid_path)
      scientific_name = @org_validator.get_organism_name(taxonomy_id)
      #scientific_nameがあり、ユーザの入力値と一致する。tax_id=1(新規生物)が入力された場合にもエラーは出力する
      if !scientific_name.nil? && scientific_name == organism_name && taxonomy_id != OrganismValidator::TAX_ROOT
        retuls = true
      else
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Path", value: [taxid_path, orgname_path]},
          {key: "OrganismName", value: organism_name},
          {key: "taxID", value: taxonomy_id}
        ]
        if scientific_name.nil? || taxonomy_id == OrganismValidator::TAX_ROOT
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        else #taxonomy_idのscientific_nameで自動補正する
          annotation.push(CommonUtils::create_suggested_annotation([scientific_name], "OrganismName", orgname_path, true));
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
        end
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:BP_R0039
  # 指定された生物種名が、Taxonomy ontologyにScientific nameとして存在するかの検証
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_set_node: a bioproject set node object
  # ==== Return
  # true/false
  #
  def taxonomy_error_warning (rule_code, project_label, project_node, line_num)
    result = false
    taxid_path = "//Organism/@taxID"
    orgname_path = "//Organism/OrganismName"
    unless project_node.xpath(orgname_path).empty?
      organism_name = get_node_text(project_node, orgname_path)
      ret = @org_validator.suggest_taxid_from_name(organism_name)

      annotation = [
        {key: "Project name", value: project_label},
        {key: "Path", value: [taxid_path, orgname_path]},
        {key: "OrganismName", value: organism_name}
      ]
      if ret[:status] == "exist" #該当するtaxonomy_idがあった場合
        scientific_name = ret[:scientific_name]
        user_edit_taxid = "" #ユーザ入力のtaxid
        user_edit_taxid = get_node_text(project_node, taxid_path) unless node_blank?(project_node, taxid_path)
        if scientific_name == organism_name && user_edit_taxid == ret[:tax_id]
          result = true #ユーザ入力のorganism_nameとtax_idの組み合わせが正しい場合のみtrue
        else
          #ユーザ入力のorganism_nameがscientific_nameでない場合や大文字小文字の違いがあった場合に自動補正する
          if scientific_name != organism_name
            annotation.push(CommonUtils::create_suggested_annotation([scientific_name], "OrganismName", orgname_path, true));
          end
          if user_edit_taxid != ret[:tax_id]
            annotation.push({key: "taxID", value: user_edit_taxid})
            annotation.push(CommonUtils::create_suggested_annotation([ret[:tax_id]], "taxID", taxid_path, true));
          end
        end
      else ret[:status] == "multiple exist" #該当するtaxonomy_idが複数あった場合、taxonomy_idを入力を促すメッセージを出力
        msg = "Multiple taxonomies detected with the same organism name. Please provide the taxonomy_id to distinguish the duplicated names."
        annotation.push({key: "Message", value: msg + " taxonomy_id:[#{ret[:tax_id]}]"})
      end #該当するtaxonomy_idが無かった場合は単なるエラー
      if result == false
        unless annotation.find{|anno| anno[:is_auto_annotation] == true}.nil? #auto-annotation有
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation, true)
        else #auto-annotation無
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        end
        @error_list.push(error_hash)
      end
    end
    result
  end

  #
  # rule:BP_R0040
  # ProjectTypeTopSingleOrganismではないか
  #
  # ==== Args
  # project_label: project label for error displaying
  # project_node: a bioproject node object
  # ==== Return
  # true/false
  #
  def invalid_project_type (rule_code, project_label, project_node, line_num)
    result = true
    project_type_path = "//Project/ProjectType/ProjectTypeTopSingleOrganism"
    if !project_node.xpath(project_type_path).empty?
      annotation = [
        {key: "Project name", value: project_label},
        {key: "Path", value: "#{project_type_path}"}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      result = false
    end
    result
  end

  #
  # rule:BP_R0041
  # locus_tag_prefixのフォーマットチェック
  # 3-12文字の英数字で、数字では始まらない
  #
  # ==== Args
  # rule_code
  # sample_name サンプル名
  # locus_tag locus_tag
  # line_num
  # ==== Return
  # true/false
  #
  def invalid_locus_tag_prefix_format (rule_code, project_label, project_node, line_num)
    result = true
    locus_tag_path = "//Project/ProjectDescr/LocusTagPrefix"
    project_node.xpath(locus_tag_path).each_with_index do |locus_tag_node, idx| #XSD定義では複数記述可能
      isvalid = true
      # locus_tagが記述されて入れば
      unless node_blank?(locus_tag_node, ".")
        locus_tag = get_node_text(locus_tag_node)
        if locus_tag.size < 3 || locus_tag.size > 12 || !locus_tag =~ /^[0-9a-zA-Z]+$/ || locus_tag =~ /^[0-9]+/
          isvalid = result = false #複数ノードの一つでもエラーがあればresultをfalseとする
        end
        if isvalid == false
          annotation = [
            {key: "Project name", value: project_label},
            {key: "LocusTagPrefix", value: locus_tag},
            {key: "Path", value: ["#{locus_tag_path}[#{idx + 1}]"]}
          ]
          error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
          @error_list.push(error_hash)
        end
      end
    end
    result
  end

  #
  # node_objで指定された対象ノードに対してxpathで検索し、ノードが存在しないまたはテキストが空（空白のみを含む）だった場合にtrueを返す
  # xpathの指定がない場合は、node_obj内のルートノードの存在チェックを行う
  # 要素のテキストは子孫のテキストを含まず要素自身のテキストをチェックする
  #
  def node_blank? (node_obj, xpath = ".")
    ret = false
    target_node = node_obj.xpath(xpath)
    if target_node.empty?
      ret = true
    else
      text_value = ""
      #xPathで複数ヒットする場合は、全てのノードのテキスト表現を連結して評価する
      target_node.each do |node|
        #空白文字のみの場合もblank扱いとする
        text_value += get_node_text(node).chomp.strip
      end
      if text_value == "" #要素/属性はあるが、テキスト/値が空白である
        ret =  true
      end
    end
    ret
  end

  #
  # node_objで指定された対象ノードに対してxpathで検索し、ノードのテキストを返す
  # もしノードが存在しなければ空文字を返す
  # xpathの指定がない場合は、node_obj内のルートノードの存在チェックを行う
  # 要素のテキストは子孫のテキストを含まず要素自身のテキストをチェックする
  #
  def get_node_text (node_obj, xpath = ".")
    text_value = ""
    target_node = node_obj.xpath(xpath)
    unless target_node.empty?
      #xPathで複数ヒットする場合は、全てのノードのテキスト表現を連結して評価する
      target_node.each do |node|
        if node.class == Nokogiri::XML::Element
          #elementの場合にはelementの要素自身のテキストを検索
          target_text_node = node.xpath("text()") #子供のテキストを含まないテキスト要素を取得
          text_value += target_text_node.map {|text_node|
            text_node.text
          }.join  #前後の空白を除去した文字列を繋げて返す
        elsif node.class == Nokogiri::XML::Attr
          #attributeの場合にはattributeの値を検索
          text_value += node.text
        elsif node.class == Nokogiri::XML::Text
          text_value += node.text
        else
          unless node.text.nil?
            text_value += node.text
          end
        end
      end
    end
    text_value
  end
end
