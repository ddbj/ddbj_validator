require 'rubygems'
require 'json'
require 'erb'
require 'ostruct'
require 'geocoder'
require 'date'
require 'net/http'
require 'nokogiri'
require File.dirname(__FILE__) + "/../../../biosample_validator/lib/validator/organism_validator.rb"
require File.dirname(__FILE__) + "/../../../biosample_validator/lib/validator/ddbj_db_validator.rb"
require File.dirname(__FILE__) + "/../common_utils.rb"

#
# A class for BioProject validation
#
class MainValidator

  #
  # Initializer
  # ==== Args
  # mode: DDBJの内部DBにアクセスできない環境かの識別用。
  # "private": 内部DBを使用した検証を実行
  # "public": 内部DBを使用した検証をスキップ
  #
  def initialize
    @conf = read_config(File.absolute_path(File.dirname(__FILE__) + "/../../conf"))
    CommonUtils::set_config(@conf)

    @validation_config = @conf[:validation_config] #need?
    @org_validator = OrganismValidator.new(@conf[:sparql_config]["endpoint"])
    @error_list = []
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
      config[:xsd_path] = File.absolute_path(File.read(config_file_dir + "/xsd/Package.xsd"))
      config[:sparql_config] = JSON.parse(File.read(config_file_dir + "/sparql_config.json"))#TODO common setting
      config[:ddbj_db_config] = JSON.parse(File.read(config_file_dir + "/ddbj_db_config.json"))#TODO common setting
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
  def validate (data_xml)
    @data_file = File::basename(data_xml)
    valid_xml = not_well_format_xml("1", data_xml)
    # xml検証が通った場合のみ実行
    if valid_xml
      valid_schema = xml_data_schema("2", data_xml, @conf[:xsd_path])
      doc = Nokogiri::XML(File.read(data_xml))
      project_set = doc.xpath("//PackageSet/Package/Project")

      #各プロジェクト毎の検証
      project_set.each_with_index do |project_node, idx|
        #TODO 各プロジェクトでxpathに複数ヒットする可能性のあるものは全てをチェックするようにeachで回す事
        idx += 1
        project_name = get_bioporject_name(project_node, idx)
        identical_project_title_and_description("5", project_name, project_node, idx)
        short_project_description("6", project_name, project_node, idx)
        empty_description_for_other_relevance("7", project_name, project_node, idx)
        empty_description_for_other_subtype("8", project_name, project_node, idx)
        empty_target_description_for_other_sample_scope("9", project_name, project_node, idx)
        empty_target_description_for_other_material("10", project_name, project_node, idx)
        empty_target_description_for_other_capture("11", project_name, project_node, idx)
        empty_method_description_for_other_method_type("12", project_name, project_node, idx)
        empty_data_description_for_other_data_type("13", project_name, project_node, idx)
        empty_publication_reference("15", project_name, project_node, idx)
        missing_strain_isolate_cultivar("17", project_name, project_node, idx)
        taxonomy_at_species_or_infraspecific_rank("18", project_name, project_node, idx)
        empty_organism_description_for_multi_species("19", project_name, project_node, idx)
        metagenome_or_environmental("20", project_name, project_node, idx)
      end

      link_set = doc.xpath("//PackageSet/Package/ProjectLinks")
      #各リンク毎の検証
      link_set.each_with_index do |link_node, idx|
        invalid_umbrella_project("16", "Link", link_node, idx)
      end
    end
  end

  #
  # Returns error/warning list as the validation result
  #
  #
  def get_error_list ()
    @error_list
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
  # 正しいXML文書であるかの検証
  #
  # ==== Args
  # xml_file: xml file path
  # ==== Return
  # true/false
  #
  def not_well_format_xml (rule_code, xml_file)
    result = true
    document = Nokogiri::XML(File.read(xml_file))
    if !document.errors.empty?
      result = false
      xml_error_msg = document.errors.map {|err|
        err.to_s
      }.join("\n")
    end
    if result
      result
    else
      annotation = [
        {key: "XML file", value: @data_file},
        {key: "XML error message", value: xml_error_msg}
      ]
      error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
      @error_list.push(error_hash)
      false
    end
  end

  #
  # XSDで規定されたXMLに違反していないかの検証
  #
  # ==== Args
  # xml_file: xml file path
  # xsd_path: xsd file path
  # ==== Return
  # true/false
  #
  def xml_data_schema (rule_code, xml_file, xsd_path)
    result = true
    xsddoc = Nokogiri::XML(File.read(xsd_path), xsd_path)
    schema = Nokogiri::XML::Schema.from_document(xsddoc)
    document = Nokogiri::XML(File.read(xml_file))
    validatan_ret = schema.validate(document)
    if validatan_ret.size <= 0
      result
    else
      schema.validate(document).each do |error|
        annotation = [
          {key: "XML file", value: @data_file},
          {key: "XSD error message", value: error.message}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
      false
    end
  end

  #
  # rule:5
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
    title_path = "Project/ProjectDescr/Title"
    desc_path = "Project/ProjectDescr/Description"
    title_node = project_node.xpath(title_path)
    desc_node = project_node.xpath(desc_path)
    if !title_node.empty?  && !desc_node.empty?
      if title_node.text.strip == desc_node.text.strip
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Title", value: title_node.text},
          {key: "Description", value: desc_node.text},
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:6
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
    node_path = "Project/ProjectDescr/Description"
    target_node = project_node.xpath(node_path)
    if !target_node.empty?
      if target_node.text.gsub(" ", "").size <= 100
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
  # rule:7
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
    node_path = "Project/ProjectDescr/Relevance/Other"
    other_node = project_node.xpath(node_path)
    if !other_node.empty?
      if other_node.text.strip == ""
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
  # rule:8
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
    node_path = "Project/ProjectType/ProjectTypeTopAdmin"
    condition_node = project_node.xpath(node_path)
    if !condition_node.empty? && condition_node.attr("subtype").text.strip == "eOther"
      target_node = condition_node.xpath("DescriptionSubtypeOther")
      if target_node.empty? || target_node.text.strip == ""
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
  # rule:9
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
    node_path = "Project/ProjectType/ProjectTypeSubmission/Target"
    condition_node = project_node.xpath(node_path)
    if !condition_node.empty? && condition_node.attr("sample_scope").text.strip == "eOther"
      target_node = condition_node.xpath("Description")
      if target_node.empty? || target_node.text.strip == ""
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

  # TODO:sample_scopeとメソッド共通化した方が良いか
  # rule:10
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
    node_path = "Project/ProjectType/ProjectTypeSubmission/Target"
    condition_node = project_node.xpath(node_path)
    if !condition_node.empty? && condition_node.attr("material").text.strip == "eOther"
      target_node = condition_node.xpath("Description")
      if target_node.empty? || target_node.text.strip == ""
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

  # TODO:sample_scopeとメソッド共通化した方が良いか
  # rule:11
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
    node_path = "Project/ProjectType/ProjectTypeSubmission/Target"
    condition_node = project_node.xpath(node_path)
    if !condition_node.empty? && condition_node.attr("capture").text.strip == "eOther"
      target_node = condition_node.xpath("Description")
      if target_node.empty? || target_node.text.strip == ""
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
  # rule:12
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
    node_path = "Project/ProjectType/ProjectTypeSubmission/Method"
    condition_node = project_node.xpath(node_path)
    if !condition_node.empty? && condition_node.attr("method_type").text.strip == "eOther"
      target_node = condition_node
      if target_node.empty? || target_node.text.strip == ""
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
  # rule:13
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
    node_path = "Project/ProjectType/ProjectTypeSubmission/Objectives/Data"
    condition_node = project_node.xpath(node_path)
    if !condition_node.empty? && condition_node.attr("data_type").text.strip == "eOther"
      target_node = condition_node
      if target_node.empty? || target_node.text.strip == ""
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
  # rule:15
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
    node_path = "Project/ProjectDescr/Publication"
    condition_node = project_node.xpath(node_path + "/DbType")
    if !condition_node.empty? && condition_node.text.strip == "eNotAvailable"
      target_node = project_node.xpath(node_path + "/Reference")
      if target_node.empty? || target_node.text.strip == ""
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
  # rule:16
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
    accession_path = "//Link/Hierarchical/MemberID/@accession"
    unless node_blank?(link_node, accession_path)
      accession_node = link_node.xpath(accession_path)
      accession_node.each do |accession_attr_node|
        unless accession_attr_node.text.chomp.strip == ""
          bioproject_accession = accession_attr_node.text.chomp.strip
          is_umbrella = @db_validator.umbrella_project?(bioproject_accession)
          if !is_umbrella
            annotation = [
             {key: "Project name", value: "None"},
             {key: "BioProject accession", value: bioproject_accession},
             {key: "Path", value: accession_path}
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
  # rule:17
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
    if !monoisolate.empty? #eMonoisolateである場合にチェック
      if ( node_blank?(project_node, "//Organism/Label") \
           && node_blank?(project_node, "//Organism/Strain") \
           && node_blank?(project_node, "//Organism/Strain/IsolateName") \
           && node_blank?(project_node, "//Organism/Strain/Breed") \
           && node_blank?(project_node, "//Organism/Strain/Cultivar"))
        annotation = [
          {key: "Project name", value: project_label},
          {key: "Path", value: "//Organism/Label | //Organism/Strain | //Organism/Strain/IsolateName | //Organism/Strain/Breed | //Organism/Strain/Cultivar"}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
        result = false
      end
    end
    result
  end

  #
  # rule:18
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
    #eMultispeciesでない場合にチェック. sample_scopeが他の値やsample_scope属性がない場合も含む
    tax_id = nil
    unless node_blank?(project_node, "//Organism/@taxID")
      tax_id = project_node.xpath("//Organism/@taxID").text.chomp.strip
    else
      unless node_blank?(project_node, "//OrganismName")
        organism_name = project_node.xpath("//OrganismName").text.chomp.strip
        ret = @org_validator.suggest_taxid_from_name(organism_name)
        if ret[:status] == "exist"
          tax_id = ret[:tax_id]
        end
      end
    end
    unless tax_id.nil? #taxID,OrganismName共に記述がない場合はチェックしない
      multispecies = project_node.xpath("//Target[@sample_scope='eMultispecies']")
      if multispecies.empty? #eMultispeciesではない場合にチェックする
        # tax_idが記述されていればtax_idを記載し、なければorganism_nameからtax_idを取得する
        result = @org_validator.is_infraspecific_rank(tax_id)
        if result == false
          annotation = [
            {key: "Project name", value: project_label},
            {key: "Path", value: "//Organism/@taxID | //OrganismName"}
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
  # rule:19
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
  # rule:20
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
    # tax_idが記述されていればtax_idを記載し、なければorganism_nameからtax_idを取得する
    # TODO rule18と同じコードまとめたい
    tax_id = nil
    unless node_blank?(project_node, "//Organism/@taxID")
      tax_id = project_node.xpath("//Organism/@taxID").text.chomp.strip
    else
      unless node_blank?(project_node, "//OrganismName")
        organism_name = project_node.xpath("//OrganismName").text.chomp.strip
        ret = @org_validator.suggest_taxid_from_name(organism_name)
        if ret[:status] == "exist"
          tax_id = ret[:tax_id]
        end
      end
    end
    unless tax_id.nil? #taxID,OrganismName共に記述がない場合はチェックしない
      environment = project_node.xpath("//Target[@sample_scope='eEnvironment']")
      unless environment.empty? #eEnvironmentである場合にチェック
        #TODO tax_id がmetagenome配下かどうか
        linages = [OrganismValidator::TAX_UNCLASSIFIED_SEQUENCES]
        unless @org_validator.has_linage(tax_id, linages) &&  @org_validator.get_organism_name(tax_id).end_with?("metagenome")
          annotation = [
            {key: "Project name", value: project_label},
            {key: "Path", value: "//Organism/@taxID | //OrganismName"}
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
  # rule:21
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
    locus_tag_nodes = project_node.xpath("//ProjectDescr/LocusTagPrefix")
    locus_tag_nodes.each do |locus_tag_node| #XSD定義では複数記述可能
      isvalid = true
      # locus_tagとbiosampleのどちらか指定が欠けているればエラー
      if (node_blank?(locus_tag_node, ".") || node_blank?(locus_tag_node, "@biosample_id"))
        isvalid = result = false #複数ノードの一つでもエラーがあればresultをfalseとする
      else
        # biosample_idからDB検索してlocus_tag_prefixが取得できない、値が異なる場合にエラー
        biosample_accession = locus_tag_node.xpath("@biosample_id").text
        locus_tag_prefix = locus_tag_node.xpath("text()").text
        bp_locus_tag_prefix =  @db_validator.get_biosample_locus_tag_prefix(biosample_accession)
        if bp_locus_tag_prefix.nil?
          isvalid = result = false
        else
          # get_biosample_locus_tag_prefixはハッシュの配列で返ってくる.findで検索して一つも合致しなければエラー
          if bp_locus_tag_prefix.find{|row| row["locus_tag_prefix"] == locus_tag_node.xpath("text()").text}.nil?
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
        annotation.push({key: "Path", value: "['//ProjectDescr/LocusTagPrefix', '//ProjectDescr/LocusTagPrefix/@biosample_id']"})
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
    end
    result
  end

  #
  # rule:22
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
    biosample_id_nodes = project_node.xpath("//ProjectDescr/LocusTagPrefix/@biosample_id")
    biosample_id_nodes.each do |biosample_id_node|
      isvalid = true
      unless node_blank?(biosample_id_node, ".") #属性値がある
        biosample_accession = biosample_id_node.text
        p biosample_accession
        if biosample_accession =~ /^SAMD\d{8}$/ || biosample_accession =~ /^SSUB\d{6}$/
          p biosample_accession
          #DBにIDがあるか検証する
          unless @db_validator.is_valid_biosample_id?(biosample_accession)
            isvalid = result = false
          end
        else
          isvalid = result = false
        end
      end
      if isvalid == false
        annotation = [
          {key: "Project name", value: project_label},
          {key: "biosample_id", value: biosample_accession},
          {key: "Path", value: "//ProjectDescr/LocusTagPrefix/@biosample_id"}
        ]
        error_hash = CommonUtils::error_obj(@validation_config["rule" + rule_code], @data_file, annotation)
        @error_list.push(error_hash)
      end
    end
    result
  end

  #
  # 指定されたxPathのノードが存在しない、またはテキストが空白だった場合にtrueを返す
  # TODO commonに移してテストコードを書く
  def node_blank? (node_obj, xpath)
    ret = false
    target_node = node_obj.xpath(xpath)
    if target_node.empty?
      ret = true
    else
      text_value = ""
      target_node.each do |node|
        if node.class == Nokogiri::XML::Element
          #elementの場合にはelementの要素自身のテキストを検索
          target_text_node = node.xpath("text()") #子供のテキストを含まないテキスト要素を取得
          text_value += target_text_node.map {|text_node|
            text_node.text.chomp.strip
          }.join  #前後の空白を除去した文字列を繋げて返す
        elsif node.class == Nokogiri::XML::Attr
          #attributeの場合にはattributeの値を検索
          text_value += node.text.chomp.strip
        end
      end
      if text_value == "" #要素/属性はあるが、テキスト/値が空白である
        ret =  true
      end
    end
    ret
  end

end
