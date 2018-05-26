require 'pg'
require 'yaml'

class DDBJDbValidator
  BIOPROJCT_DB_NAME = "bioproject"
  BIOSAMPLE_DB_NAME = "biosample"
  DRA_DB_NAME = "drmdb"
  SUBMITTER_DB_NAME = "submitterdb"

  def initialize (config)
    @pg_host = config["pg_host"]
    @pg_port = config["pg_port"]
    @pg_user = config["pg_user"]
    @pg_pass = config["pg_pass"]
  end

  #
  # 指定されたBioSample Accession IDが有効なIDであるかを返す
  # DBにない場合や、statusが5600,5700の場合にはfalseを返す
  #
  # ==== Args
  # bioproject_acceccion ex. "PSUB004142", "PRJDB3490"
  # ==== Return
  # true/false
  #
  def valid_bioproject_id?(bioproject_accession)
    return nil if bioproject_accession.nil?
    result = false
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', BIOPROJCT_DB_NAME, @pg_user,  @pg_pass)

      if bioproject_accession =~ /^PSUB\d{6}/
        psub_query_id = bioproject_accession

        q = "SELECT *
             FROM mass.submission sub 
              LEFT OUTER JOIN mass.project p USING(submission_id)
             WHERE sub.submission_id = $1
               AND (p.status_id IS NULL OR p.status_id NOT IN (5600, 5700))"
        prj_query_id = "#{psub_query_id}"
      elsif bioproject_accession =~ /^PRJDB\d+/
        prjd_query_id = bioproject_accession.gsub("PRJDB", "").to_i

        q = "SELECT *
             FROM mass.submission sub 
              LEFT OUTER JOIN mass.project p USING(submission_id)
             WHERE p.project_id_counter = $1
              AND (p.status_id IS NULL OR p.status_id NOT IN (5600, 5700))"
        prj_query_id = "#{prjd_query_id}"
      else
        return false
      end
      connection.prepare("pre_query", q)
      res = connection.exec_prepared("pre_query", [prj_query_id])
      if 1 == res.ntuples then
        result = true
      end
    rescue => ex
      message = "Failed to execute the query to DDBJ '#{BIOPROJCT_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end
    result
  end

  #
  # 指定されたBioSample Accession IDを参照許可submitter_idの配列返す
  # DBにない場合や、statusが5600,5700の場合には空の配列を返す
  #
  # ==== Args
  # bioproject_acceccion ex. "PSUB004142", "PRJDB3490"
  # ==== Return
  # submitter_idの配列
  # [ "test01", "test02" ]
  #
  def get_bioproject_referenceable_submitter_ids(bioproject_accession)
    return nil if bioproject_accession.nil?
    result = []

    #無効なbioproject_idが指定された場合には空の配列を返す
    if (bioproject_accession =~ /^PSUB\d{6}/ || bioproject_accession =~ /^PRJDB\d+/)
      if !valid_bioproject_id?(bioproject_accession)
        return []
      end
    end
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', DRA_DB_NAME, @pg_user,  @pg_pass)

      if bioproject_accession =~ /^PSUB\d{6}/
        prj_query_id = bioproject_accession
      elsif bioproject_accession =~ /^PRJDB\d+/
        prj_query_id = get_bioproject_submission(bioproject_accession)
      else #外部ID(PRJNA,PRJDA等)
        prj_query_id = bioproject_accession
      end

      q = "SELECT submitter_id
           FROM mass.ext_entity
             JOIN mass.ext_permit USING(ext_id)
           WHERE status = 100
             AND ref_name = $1"

      connection.prepare("pre_query", q)
      res = connection.exec_prepared("pre_query", [prj_query_id])
      res.each do |item|
        result.push(item["submitter_id"])
      end
    rescue => ex
      message = "Failed to execute the query to DDBJ '#{BIOPROJCT_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end
    result
  end

  
  #
  # 指定されたBioSample Accession IDがUmbrella projectである場合にtrueを返す
  # Umbrella projectではない、または無効なBioSample Accession IDである場合にはfalseを返す
  #
  # ==== Args
  # bioproject_acceccion ex. "PSUB990036", "PRJDB3549"
  # ==== Return
  # true/false
  #
  def umbrella_project? (bioproject_accession)
    result = false
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', BIOPROJCT_DB_NAME, @pg_user,  @pg_pass)

      if bioproject_accession =~ /^PSUB\d{6}/
        psub_query_id = bioproject_accession

        q = "SELECT COUNT(*)
             FROM mass.project p 
             WHERE p.submission_id = $1
              AND p.project_type = 'umbrella'
              AND (p.status_id IS NULL OR p.status_id NOT IN (5600, 5700))"
        prj_query_id = "#{psub_query_id}"
      elsif bioproject_accession =~ /^PRJDB\d+/
        prjd_query_id = bioproject_accession.gsub("PRJDB", "").to_i

        q = "SELECT COUNT(*)
             FROM mass.project p 
             WHERE p.project_id_counter = $1
              AND p.project_type = 'umbrella'
              AND (p.status_id IS NULL OR p.status_id NOT IN (5600, 5700))"
        prj_query_id = "#{prjd_query_id}"
      else
        return false
      end

      connection.prepare("pre_query", q)
      res = connection.exec_prepared("pre_query", [prj_query_id])
      # if "count" >= 1 this bioproject_accession is  umbrella id
      if res[0]["count"].to_i > 0
        result = true
      end

    rescue => ex
      message = "Failed to execute the query to DDBJ '#{BIOPROJCT_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end
    result
  end

  #
  # 指定されたsubmitter_idに紐付くプロジェクトのproject_name名をリストで返す
  #
  # ==== Args
  # submitter_id
  # ==== Return
  # project_nameのリスト。一つもない場合にも空のリストを返す
  # [ "project name 1", "project name 2", ...]
  #
  def get_bioproject_names (submitter_id)
    bioproject_name_list = []
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', BIOPROJCT_DB_NAME, @pg_user,  @pg_pass)
      q = "SELECT submitter_id, submission_id, data_value AS bioproject_name
           FROM mass.submission_data
           LEFT OUTER JOIN mass.submission USING(submission_id)
           WHERE data_name = 'project_name'
            AND submitter_id = $1
            AND (status_id IS NULL OR status_id NOT IN (5600, 5700))"

      connection.prepare("pre_query", q)
      res = connection.exec_prepared("pre_query", [submitter_id])

      res.each do |item|
        unless item["bioproject_name"].empty?
          bioproject_name_list.push(item["bioproject_name"])
        end
      end

    rescue => ex
      message = "Failed to execute the query to DDBJ '#{BIOPROJCT_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end

    bioproject_name_list
  end

  #
  # 指定されたsubmitter_idに紐付くプロジェクトのtitleとdescriptionをカンマ連結した文字列をリストで返す
  #
  # ==== Args
  # submitter_id
  # ==== Return
  # project_nameのリスト。一つもない場合にも空のリストを返す
  # [ "project name 1", "project name 2", ...]
  #
  def get_bioproject_title_descs  (submitter_id)
    bioproject_title_desc_list = []
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', BIOPROJCT_DB_NAME, @pg_user,  @pg_pass)
      q = "SELECT submitter_id, submission_id, data_name, data_value
           FROM mass.submission_data
           LEFT OUTER JOIN mass.submission USING(submission_id)
           WHERE (data_name = 'project_title' OR data_name = 'public_description')
            AND submitter_id = $1
            AND (status_id IS NULL OR status_id NOT IN (5600, 5700))"

      connection.prepare("pre_query", q)
      res = connection.exec_prepared("pre_query", [submitter_id])

      #属性(title, description)毎に行が出力されるので、submission_id単位でグルーピングし、
      #それぞれの属性の値を取得した後、カンマで連結してリストに格納する
      res.group_by {|item| item["submission_id"]}.each do |submission, data_list|
        title = data_list.select {|data| data["data_name"] == "project_title"}.first["data_value"]
        desc = data_list.select {|data| data["data_name"] == "public_description"}.first["data_value"]
        bioproject_title_desc_list.push([title, desc].join(","))
      end

    rescue => ex
      message = "Failed to execute the query to DDBJ '#{BIOPROJCT_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end

    bioproject_title_desc_list
  end

  #
  # 指定されたsubmission_idのサンプルのサンプル名をリストで返す
  #
  # ==== Args
  # submission_id ex. "SSUB003677"
  # ==== Return
  # サンプル名のリスト。一つもない場合にも空のリストを返す
  # [ "sample 1", "sample 2", ...]
  #
  def get_sample_names (submission_id)
    sample_name_list = []
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', BIOSAMPLE_DB_NAME, @pg_user,  @pg_pass)

      q = "SELECT smp.sample_name
            FROM mass.sample smp
            WHERE smp.submission_id = $1
              AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"

      connection.prepare("pre_query", q)
      res = connection.exec_prepared("pre_query", [submission_id])
      res.each do |item|
        unless item["sample_name"].empty?
          sample_name_list.push(item["sample_name"])
        end
      end

    rescue => ex
      message = "Failed to execute the query to DDBJ '#{BIOSAMPLE_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end
    sample_name_list
  end

  #
  # PSUB IDに対応するBioProject ID(Accession ID)があれば返す
  # なければnilを返す
  #
  # ==== Args
  # psub_id PSUBから始まるID ex."PSUB004142"
  # ==== Return
  #
  #
  def get_bioproject_accession(psub_id)
    result = nil
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', BIOPROJCT_DB_NAME, @pg_user,  @pg_pass)
      q = "SELECT p.project_id_counter prj_id, p.project_id_prefix prefix
           FROM mass.project p
           WHERE p.submission_id = $1
            AND p.project_id_counter IS NOT NULL
            AND p.project_id_prefix IS NOT NULL
            AND (p.status_id IS NULL OR p.status_id NOT IN (5600, 5700))"

      connection.prepare("pre_query", q)
      res = connection.exec_prepared("pre_query", [psub_id])
      if 1 == res.ntuples then ## 2つ以上返ってきてもエラー扱い
        result = res[0]["prefix"] + res[0]["prj_id"]
      end

    rescue => ex
      message = "Failed to execute the query to DDBJ '#{BIOPROJCT_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end
    result
  end

  #
  # BioProject ID(Accession ID)に対応するPSUB IDがあれば返す
  # なければnilを返す
  #
  # ==== Args
  # bioproject_accession PRJDBから始まるID ex."PRJDB3490"
  # ==== Return
  #
  #
  def get_bioproject_submission(bioproject_accession)
    result = nil

    unless bioproject_accession =~ /^PRJDB\d+/
      return nil
    end
    begin
      project_id_counter = bioproject_accession.gsub("PRJDB", "").to_i
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', BIOPROJCT_DB_NAME, @pg_user,  @pg_pass)
      q = "SELECT p.submission_id
           FROM mass.project p
           WHERE p.project_id_counter = $1
            AND (p.status_id IS NULL OR p.status_id NOT IN (5600, 5700))"

      connection.prepare("pre_query", q)
      res = connection.exec_prepared("pre_query", [project_id_counter])
      if 1 == res.ntuples then ## 2つ以上返ってきてもエラー扱い
        result = res[0]["submission_id"]
      end

    rescue => ex
      message = "Failed to execute the query to DDBJ '#{BIOPROJCT_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end
    result
  end

  #
  # biosample databaseに存在するlocus_tag_prefixとSSUBのセットを取得してリストで返す
  #
  # ==== Args
  # ==== Return
  # SSUBとlocus_tag_prefixのリスト。一つもない場合にも空のリストを返す
  # [
  #   {submission_id: "SSUBNNNNNN", locus_tag_prefix: "XXA" },
  #   {submission_id: "SSUBNNNNNN", locus_tag_prefix: "XXB" }, ...
  # ]
  #
  def get_all_locus_tag_prefix
    prefix_list = []
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', BIOSAMPLE_DB_NAME, @pg_user,  @pg_pass)

      q = "SELECT smp.submission_id, attr.attribute_value
           FROM mass.attribute attr
            JOIN mass.sample smp USING (smp_id)
           WHERE attribute_name = 'locus_tag_prefix' AND attribute_value <> ''
            AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"

      connection.prepare("pre_query", q)
      res = connection.exec_prepared("pre_query")

      res.each do |item|
        unless item["attribute_value"].empty?
          hash = {submission_id: item["submission_id"], locus_tag_prefix: item["attribute_value"]}
          prefix_list.push(hash)
        end
      end

    rescue => ex
      message = "Failed to execute the query to DDBJ '#{BIOSAMPLE_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end

    prefix_list
  end

  #
  # 指定されたBioSample Accession IDのlocus_tag_prefix属性の値を返す
  # DBにない場合にはnilを返す
  # TODO 複数返す可能性があるか質問する. Submission IDであれば複数のbiosample_idに紐付くため発生しそう
  #
  # ==== Args
  # biosample_acceccion ex. "SSUB000020", "SAMD00000007"
  # ==== Return
  # BioSampleのIDとlocus_tag_prefix情報のハッシュ
  # [
  #   {
  #     "accession_id" => "SAMD00000007",
  #     "submission_id" => "SSUB000020",
  #     "locus_tag_prefix" => "ATW"
  #   }, ...
  #
  def get_biosample_locus_tag_prefix(biosample_accession)
    return nil if biosample_accession.nil?
    result = nil
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', BIOSAMPLE_DB_NAME, @pg_user,  @pg_pass)

      if biosample_accession =~ /^SSUB\d{6}/
        ssub_query_id = biosample_accession

        q = "SELECT attr.attribute_value AS locus_tag_prefix, acc.accession_id, smp.submission_id
             FROM mass.sample smp
               LEFT OUTER JOIN mass.accession acc USING(smp_id)
               JOIN mass.attribute attr USING(smp_id)
             WHERE attr.attribute_name = 'locus_tag_prefix'
               AND attr.attribute_value != ''
               AND smp.submission_id = $1
               AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"
        smp_query_id = ssub_query_id
      elsif biosample_accession =~ /^SAMD\d+/
        samd_query_id = biosample_accession

        q = "SELECT attr.attribute_value AS locus_tag_prefix, acc.accession_id, smp.submission_id
             FROM mass.sample smp
               LEFT OUTER JOIN mass.accession acc USING(smp_id)
               JOIN mass.attribute attr USING(smp_id)
             WHERE attr.attribute_name = 'locus_tag_prefix'
               AND attr.attribute_value != ''
               AND acc.accession_id = $1
               AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"
        smp_query_id = samd_query_id
      else
        return nil
      end

      connection.prepare("pre_query", q)
      res = connection.exec_prepared("pre_query", [smp_query_id])
      if 1 <= res.ntuples then
        result = res
      end
      result
    rescue => ex
      message = "Failed to execute the query to DDBJ '#{BIOSAMPLE_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end
  end

  #
  # 指定されたBioSample AccessionがDBに登録されていればtrueを返す
  #
  # ==== Args
  # biosample_acceccion ex. "SAMD00025188", "SSUB003675"
  # ==== Return
  # true/false
  #
  def is_valid_biosample_id?(biosample_accession)
    return nil if biosample_accession.nil?
    result = nil
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', BIOSAMPLE_DB_NAME, @pg_user,  @pg_pass)

      if biosample_accession =~ /^SSUB\d{6}/
        ssub_query_id = biosample_accession

        q = "SELECT DISTINCT sub.submitter_id, acc.accession_id, sub.submission_id
             FROM mass.sample smp
               LEFT OUTER JOIN mass.accession acc USING(smp_id)
               LEFT OUTER JOIN mass.submission sub USING(submission_id)
             WHERE smp.submission_id = $1
               AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"
        smp_query_id = ssub_query_id
      elsif biosample_accession =~ /^SAMD\d+/
        samd_query_id = biosample_accession

        q = "SELECT DISTINCT sub.submitter_id, acc.accession_id, sub.submission_id
             FROM mass.sample smp
               LEFT OUTER JOIN mass.accession acc USING(smp_id)
               LEFT OUTER JOIN mass.submission sub USING(submission_id)
             WHERE acc.accession_id = $1
               AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"
        smp_query_id = samd_query_id
      else
        return nil
      end

      connection.prepare("pre_query", q)
      res = connection.exec_prepared("pre_query", [smp_query_id])
      if 1 <= res.ntuples then
        result = true
      else
        result = false
      end
      result
    rescue => ex
      message = "Failed to execute the query to DDBJ '#{BIOSAMPLE_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end
    result
  end

  #
  # 指定されたsubmitter_idのOrganizationの情報を返す。submitter_idが存在しなければnilを返す
  #
  # ==== Args
  # submitter_id ex. "test01"
  # ==== Return
  # submitterのorganization情報のハッシュ
  # {
  #   "submitter_id" => "test01",
  #   "center_name" => "National Institute of Genetics",
  #   "organization" => "DNA Data Bank of Japan",
  #   "department" => "Database Division",
  #   "affiliation" => "affiliation name",
  #   "unit" => "unit name"
  # }
  #
  def get_submitter_organization(submitter_id)
    return nil if submitter_id.nil?
    result = nil
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', SUBMITTER_DB_NAME, @pg_user,  @pg_pass)

      q = "SELECT submitter_id, center_name, organization, department, affiliation, unit FROM mass.organization WHERE submitter_id = $1"

      connection.prepare("pre_query", q)
      res = connection.exec_prepared("pre_query", [submitter_id])
      if 1 == res.ntuples then
        result = res[0]
      end
    rescue => ex
      message = "Failed to execute the query to DDBJ '#{SUBMITTER_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end
    result
  end

  #
  # 指定されたsubmitter_idのcenter_nameを返す。submitter_idまたはcenter_nameが存在しなければnilを返す
  #
  # ==== Args
  # submitter_id ex. "test01"
  # ==== Return
  # submitterのcenter_name: e.g. "National Institute of Genetics"
  #
  def get_submitter_center_name(submitter_id)
    center_name = nil
    org_info = get_submitter_organization(submitter_id)
    if !org_info.nil?
      center_name = org_info["center_name"]
    end
    center_name
  end

  #
  # 指定されたsubmitter_idのContact情報のリストを返す。submitter_idが存在しなければnilを返す
  #
  # ==== Args
  # submitter_id ex. "test01"
  # ==== Return
  # submitterのContact情報のリスト
  # [
  #   {
  #     "submitter_id" => "test01",
  #     "email" => "test@mail.com",
  #     "first_name" => "Taro",
  #     "middle_name" => "Genome",
  #     "last_name" => "Mishima"
  #   }, ..
  # ]
  #
  def get_submitter_contact_list(submitter_id)
    return nil if submitter_id.nil?
    result = nil
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', SUBMITTER_DB_NAME, @pg_user,  @pg_pass)

      q = "SELECT submitter_id, email, first_name, middle_name, last_name FROM mass.contact WHERE submitter_id = $1 and is_pi = true"

      connection.prepare("pre_query", q)
      res = connection.exec_prepared("pre_query", [submitter_id])
      if res.ntuples > 0 then
        result = res
      end
    rescue => ex
      message = "Failed to execute the query to DDBJ '#{SUBMITTER_DB_NAME}'.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    ensure
      connection.close if connection
    end
    result
  end

end
