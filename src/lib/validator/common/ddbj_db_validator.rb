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
    @pg_timeout = config["pg_timeout"]
  end

  def get_connection(db_name)
    begin
      connection = PG::Connection.connect({host: @pg_host, port: @pg_port, dbname: db_name, user: @pg_user, password: @pg_pass, connect_timeout: @pg_timeout})
      state_timeout = (@pg_timeout * 1000).to_s #millsec
      connection.exec("SET SESSION statement_timeout = #{state_timeout}") ## 一定時間応答がなければエラーを発生させるように設定
      connection
    rescue => ex
      raise ex
    end
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
      connection = get_connection(BIOPROJCT_DB_NAME)

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
  # 指定されたBioProject Accession IDを参照許可submitter_idの配列返す
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
      connection = get_connection(DRA_DB_NAME)

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
      connection = get_connection(BIOPROJCT_DB_NAME)

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
  # 指定されたsubmitter_idに紐付くプロジェクトのnameとtitle,descriptionをリストで返す
  #
  # ==== Args
  # submitter_id
  # ==== Return
  # project_name, title, descriptionのリスト。一つもない場合にも空のリストを返す
  # [ {submission_id: "PSUBxxx", project_name: "project name1", bioproject_title: "project title1", public_description:  "project desc1"},
  #   {submission_id: "PSUBxxx", project_name: "project name2", bioproject_title: "project title2", public_description:  "project desc2"}, ...
  # ]
  #
  def get_bioproject_names_list  (submitter_id)
    return [] if submitter_id.nil?
    bioproject_title_desc_list = []
    begin
      connection = get_connection(BIOPROJCT_DB_NAME)
      q = "SELECT submitter_id, submission_id, data_name, data_value
           FROM mass.project p
           LEFT OUTER JOIN mass.submission_data sd USING(submission_id)
           LEFT OUTER JOIN mass.submission s USING(submission_id)
           WHERE (data_name = 'project_name' OR data_name = 'project_title' OR data_name = 'public_description')
           AND submitter_id = $1
           AND (p.status_id IS NULL OR p.status_id NOT IN (5600, 5700))"

      connection.prepare("pre_query", q)
      res = connection.exec_prepared("pre_query", [submitter_id])

      #属性(name, title, description)毎に行が出力されるので、submission_id単位でグルーピングし、
      #それぞれの属性の値を取得した後、カンマで連結してリストに格納する
      keys = ["project_name", "project_title", "public_description"]
      res.group_by {|item| item["submission_id"]}.each do |submission, data_list|
        hash = {}
        keys.each do |key|
          values_list = data_list.select {|data| data["data_name"] == key}
          if values_list.size == 1
            hash[key.to_sym] = values_list.first["data_value"]
          elsif values_list.size > 1
            hash[key.to_sym] = values_list.map{|item| item["data_value"]}.uniq.join(", ")
          else
            hash[key.to_sym] = ""
          end
        end
        bioproject_title_desc_list.push(hash)
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
      connection = get_connection(BIOSAMPLE_DB_NAME)

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
      connection = get_connection(BIOPROJCT_DB_NAME)
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
      connection = get_connection(BIOPROJCT_DB_NAME)
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
      connection = get_connection(BIOSAMPLE_DB_NAME)

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
      connection = get_connection(BIOSAMPLE_DB_NAME)

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
      connection = get_connection(BIOSAMPLE_DB_NAME)

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
      connection = get_connection(SUBMITTER_DB_NAME)

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
      connection = get_connection(SUBMITTER_DB_NAME)

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

  #
  # 指定されたRUN accession idのリストに対して、各IDがDBで有効なIDであるか検証してフラグをつけて返す
  #
  # ==== Args
  # run_accession_list ex. ["DRR060518", "DRR000000"]
  # ==== Return
  # 存在フラグを付与したリスト ex. [{accession_id: "DRR060518", is_exist: true}, {accession_id: "DRR000000", is_exist: false}]
  #
  def exist_check_run_ids(run_accession_list)
    return nil if run_accession_list.nil?
    run_with_submitter_list = get_run_submitter_ids(run_accession_list)
    result = []
    # submitter_idが取得できればそのRUN IDは有効であるとみなす
    run_with_submitter_list.each do |run|
      hash = {accession_id: run[:run_id]}
      if run[:submitter_id].nil?
        hash[:is_exist] = false
      else
        hash[:is_exist] = true
      end
      result.push(hash)
    end
    result
  end

  #
  # 指定されたBioSampl accession idのリストに対して、IDがDBで有効な場合にメタデータをs取得して返す
  #
  # ==== Args
  # biosample_accession_list ex. ["SAMD00052344", "SAMD00052345", "SAMD00000000"]
  # ==== Return
  # biosample accession idをキーとしたハッシュ。
  # BioSample情報が取得できなかったIDは含まない
  # ==== Return
  # accession id毎のBioSampleのメタデータ
  # {
  #  "SAMD00052344": {
  #                    attribute_list: [
  #                      {attribute_name: "bioproject_id", attribute_value: "PRJDB4841"},
  #                      {attribute_name: "collection_date", attribute_value: "missing"}, ... # 空白は除外されるが"missing"や""NA"は取得される
  #                    ]
  #                  },
  #  "SAMD00052345": {
  #                    attribute_list: [
  #                      {attribute_name: "bioproject_id", attribute_value: "PRJDB4841"},
  #                      {attribute_name: "collection_date", attribute_value: "missing"}, ...
  #                    ]
  #                  },
  #  }
  #  SAMD00000000 はdbから値が取得できないため結果には含まれない
  #
  def get_biosample_metadata(biosample_accession_list)
    return {} if biosample_accession_list.nil? || biosample_accession_list.size == 0
    sample_id_list = []
    biosample_accession_list.each do |accession_id|
      if accession_id =~ /^SAMD\d+/
        sample_id_list.push(accession_id)
      end
    end
    if sample_id_list.size == 0
      return {}
    else
      id_place_holder = (1..sample_id_list.size).map{|idx| "$" + idx.to_s}.join(",")
      begin
        connection = get_connection(BIOSAMPLE_DB_NAME)

        q = "SELECT attr.attribute_name, attr.attribute_value, acc.accession_id
             FROM mass.sample smp
               JOIN mass.accession acc USING(smp_id)
               JOIN mass.attribute attr USING(smp_id)
             WHERE
               acc.accession_id IN (#{id_place_holder})
               AND attr.attribute_value != ''
               AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"
        connection.prepare("pre_query", q)
        res = connection.exec_prepared("pre_query", sample_id_list)

        result = {}
        res.group_by{|row| row["accession_id"]}.each do |acc_id, ret_list|
          result[acc_id.to_s] = {attribute_list: []}
          ret_list.each do |row|
            result[acc_id.to_s][:attribute_list].push({attribute_name: row["attribute_name"], attribute_value: row["attribute_value"]})
          end
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
  end

  #
  # 指定されたBioProject Accession IDに対するsubmitter_idを付与して配列で返す
  # IDがDBにない場合や、statusが5600,5700の場合にはsubmitter_idを付与しない
  #
  # ==== Args
  # bioproject_accession_list ex. ["PRJDB3490", "PRJDB00000", "PSUB004141"]
  # ==== Return
  # accession_idとsubmitter_idの配列
  # [ {bioproject_id: "PRJDB3490", submitter_id: "sgibbons"}, {bioproject_id: "PRJDB00000"},  {bioproject_id: "PSUB004141"}]
  #
  def get_bioproject_submitter_ids(bioproject_accession_list)
    return nil if bioproject_accession_list.nil?
    result = []
    prj_counter_id_list = []
    bioproject_accession_list.each do |bioproject_accession|
      result.push({bioproject_id: bioproject_accession})
      if bioproject_accession =~ /^PRJDB\d+/
        prj_counter_id_list.push(bioproject_accession.gsub("PRJDB", "").to_i)
      end
    end

    if prj_counter_id_list.size > 0
      begin
        connection = get_connection(BIOPROJCT_DB_NAME)

        id_place_holder = (1..prj_counter_id_list.size).map{|idx| "$" + idx.to_s}.join(",")

        q = "SELECT project_id_prefix, project_id_counter, submitter_id
             FROM mass.submission sub
              LEFT OUTER JOIN mass.project p USING(submission_id)
             WHERE p.project_id_counter IN (#{id_place_holder})
              AND (p.status_id IS NULL OR p.status_id NOT IN (5600, 5700))"
        connection.prepare("pre_query", q)
        res = connection.exec_prepared("pre_query", prj_counter_id_list)

        res.each do |row|
          # 結果が返ってきたBioProjectがあればsubmitter_id情報を足す
          bioproject_accession_id = "#{row["project_id_prefix"]}#{row["project_id_counter"]}"
          selected = result.select{|bioproject| bioproject[:bioproject_id] == bioproject_accession_id}
          selected.each{|ret| ret[:submitter_id] = row["submitter_id"]}
        end

      rescue => ex
        message = "Failed to execute the query to DDBJ '#{BIOPROJCT_DB_NAME}'.\n"
        message += "#{ex.message} (#{ex.class})"
        raise StandardError, message, ex.backtrace
      ensure
        connection.close if connection
      end
    end
    result
  end

  #
  # 指定されたBioSample Accession IDに対するsubmitter_idを付与して配列で返す
  # IDがDBにない場合や、statusが5600,5700の場合にはsubmitter_idを付与しない
  #
  # ==== Args
  # biosample_accession_list ex. ["SAMD00000001", "SAMDB00000", "SSUB001848"]
  # ==== Return
  # accession_idとsubmitter_idの配列
  # [ {biosample_id: "SAMD00000001", submitter_id: "sokazaki"}, {biosample_id: "SAMDB00000"},  {biosample_id: "SSUB001848"}]
  #
  def get_biosample_submitter_ids(biosample_accession_list)
    return nil if biosample_accession_list.nil?
    result = []
    biosample_id_list = []
    biosample_accession_list.each do |biosample_accession|
      result.push({biosample_id: biosample_accession})
      if biosample_accession =~ /^SAMD\d+/
        biosample_id_list.push(biosample_accession)
      end
    end
    if biosample_id_list.size > 0
      begin
        connection = get_connection(BIOSAMPLE_DB_NAME)
        id_place_holder = (1..biosample_id_list.size).map{|idx| "$" + idx.to_s}.join(",")

        q = "SELECT DISTINCT sub.submitter_id, acc.accession_id, sub.submission_id
              FROM mass.sample smp
                JOIN mass.accession acc USING(smp_id)
                JOIN mass.submission sub USING(submission_id)
              WHERE acc.accession_id IN (#{id_place_holder})
                AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"
        connection.prepare("pre_query", q)
        res = connection.exec_prepared("pre_query", biosample_id_list)

        res.each do |row|
          # 結果が返ってきたBioSampleがあればsubmitter_id情報を足す
          selected = result.select{|biosample| biosample[:biosample_id] == row["accession_id"]}
          selected.each{|ret| ret[:submitter_id] = row["submitter_id"]}
        end
      rescue => ex
        message = "Failed to execute the query to DDBJ '#{BIOSAMPLE_DB_NAME}'.\n"
        message += "#{ex.message} (#{ex.class})"
        raise StandardError, message, ex.backtrace
      ensure
        connection.close if connection
      end
    end
    result
  end

  #
  # 指定されたDRR Accession IDに対するsubmitter_idを付与して配列で返す
  # IDがDBにない場合や、statusが900,1000,1100の場合にはsubmitter_idを付与しない
  #
  # ==== Args
  # drr_accession_list ex. ["DRR060518", "DRR000000"]
  # ==== Return
  # accession_idとsubmitter_idの配列
  # [ {run_id: "DRR060518", submitter_id: "tomohiro"}, {run_id: "DRR000000"}]
  #
  def get_run_submitter_ids(run_accession_list)
    return nil if run_accession_list.nil?
    result = []
    run_id_list = []
    run_accession_list.each do |run_accession|
      result.push({run_id: run_accession})
      if m = run_accession.chomp.strip.match(/^(?<acc_type>[D|S]RR)(?<acc_no>\d{6})$/)
        run_id_list.push({acc_type: m[:acc_type], acc_no: m[:acc_no].to_i})
      end
    end
    unless run_id_list.size == 0
      # RUN IDのパラメータ分のIN句のquery parameterを組み立てる
      # SQL側 =>  IN ( ($1, $2), ($3, $4) )
      # parameter => ["DRR", 60518, "DRR", 60519]
      query_text = ""
      param_index = 0
      query_params = []
      run_id_list.each do |param|
        query_text += ", " unless param_index == 0
        query_text += "($#{param_index += 1}, $#{param_index += 1})"
        query_params.concat([param[:acc_type], param[:acc_no]])
      end

      begin
        connection = get_connection(DRA_DB_NAME)
        q = "SELECT ent2.acc_type drr, ent2.acc_no drrno, rel.grp_id r_grp_id, g_view.status, g_view.sub_id, g_view.submitter_id
               FROM mass.accession_entity ent1
               JOIN mass.accession_relation rel ON(ent1.acc_id=rel.p_acc_id)
               JOIN mass.accession_entity ent2 ON(rel.acc_id=ent2.acc_id)
               JOIN mass.current_dra_submission_group_view g_view ON (rel.grp_id = g_view.grp_id)
             WHERE
               ent2.is_delete != TRUE
               AND g_view.status NOT IN (900, 1000, 1100)
               AND (ent2.acc_type, ent2.acc_no) IN ( #{query_text} )"

        connection.prepare("pre_query", q)
        res = connection.exec_prepared("pre_query", query_params)

        res.each do |row|
          # 結果が返ってきたRunがあればsubmitter_id情報を足す
          run_accession_id = "#{row["drr"]}#{row["drrno"].rjust(6, '0')}" # 0埋め6桁
          selected = result.select {|search_run| search_run[:run_id] == run_accession_id}
          selected.each{|ret| ret[:submitter_id] = row["submitter_id"]}
        end
      rescue => ex
        message = "Failed to execute the query to DDBJ '#{DRA_DB_NAME}'.\n"
        message += "#{ex.message} (#{ex.class})"
        raise StandardError, message, ex.backtrace
      ensure
        connection.close if connection
      end
    end
    result
  end

  #
  # 指定されたBioSample Accession IDに対するsmp_idを付与して配列で返す
  # IDがDBにない場合や、statusが5600, 5700の場合にはsmp_idを付与しない
  #
  # ==== Args
  # biosample_accession_list ex. ["SAMD00052344", "SAMD00000000"]
  # ==== Return
  # accession_idとsubmitter_idの配列
  # [ {biosample_id: "SAMD00052344", smp_id: "64274"}, {biosample_id: "SAMD00000000"}]
  #
  def get_valid_smp_id(biosample_accession_list)
    return nil if biosample_accession_list.nil?
    result = []
    biosample_id_list = []
    biosample_accession_list.each do |biosample_accession|
      result.push({biosample_id: biosample_accession})
      if biosample_accession =~ /^SAMD\d+/
        biosample_id_list.push(biosample_accession)
      end
    end
    if biosample_id_list.size > 0
      begin
        connection = get_connection(BIOSAMPLE_DB_NAME)
        id_place_holder = (1..biosample_id_list.size).map{|idx| "$" + idx.to_s}.join(",")

        q = "SELECT accession_id, smp_id
             FROM mass.accession
            JOIN mass.sample smp USING(smp_id)
            WHERE accession_id IN (#{id_place_holder})
             AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"
        connection.prepare("pre_query", q)
        res = connection.exec_prepared("pre_query", biosample_id_list)

        res.each do |row|
          # 結果が返ってきたBioSampleがあればsmp_id情報を足す
          selected = result.select{|biosample| biosample[:biosample_id] == row["accession_id"]}
          selected.each{|ret| ret[:smp_id] = row["smp_id"]}
        end
      rescue => ex
        message = "Failed to execute the query to DDBJ '#{BIOSAMPLE_DB_NAME}'.\n"
        message += "#{ex.message} (#{ex.class})"
        raise StandardError, message, ex.backtrace
      ensure
        connection.close if connection
      end
    end
    result
  end

  #
  # 指定されたBioSample の smp_id に対する BioProject Accession ID のリストを付与して配列で返す。DRA登録を通して検索する。
  # IDがDBにない場合や、statusが無効な場合にはsmp_idを付与しない
  #
  # ==== Args
  # biosample_smp_id_list ex. ["64274", "00000"]
  # ==== Return
  # smp_idとBioProject Accession IDの配列
  # [ {smp_id: "64274", bioproject_accession_id_list: ["64274"]}, {smp_id: "00000"}]
  #
  def get_bioproject_id_via_dra(biosample_smp_id_list)
    return nil if biosample_smp_id_list.nil?
    result = []
    biosample_smp_id_list.each do |smp_id|
      result.push({smp_id: smp_id})
    end
    if biosample_smp_id_list.size > 0
      begin
        connection = get_connection(DRA_DB_NAME)
        id_place_holder = (1..biosample_smp_id_list.size).map{|idx| "$" + idx.to_s}.join(",")
        # sub queryでの記述では数秒掛かるケースもあったため、クエリを分離して実行
        q = "SELECT acc_id
               FROM mass.ext_entity smp_ext
               JOIN mass.ext_relation smp_rel USING(ext_id)
             WHERE smp_ext.ref_name IN (#{id_place_holder})
               AND acc_type = 'SSUB'
              AND acc_id IS NOT NULL"
        connection.prepare("pre_query_ssub", q)
        res = connection.exec_prepared("pre_query_ssub", biosample_smp_id_list)
        if res.ntuples > 0 # hit ssub
          ssub_list = res.map{|row| row["acc_id"]}
          id_place_holder = (1..ssub_list.size).map{|idx| "$" + idx.to_s}.join(",")
          q = "SELECT DISTINCT acc_id, acc_type AS ext_acc_type, ref_name, g_view.status
                 FROM mass.ext_entity smp_ext
                 JOIN mass.ext_relation ext_ref USING(ext_id)
                 JOIN mass.current_dra_submission_group_view g_view USING(grp_id)
               WHERE ext_ref.acc_id IN (#{id_place_holder})
                 AND g_view.status NOT IN (900, 1000, 1100)"
          connection.prepare("pre_query", q)
          res = connection.exec_prepared("pre_query", ssub_list)
          res.group_by{|row| row["acc_id"]}.each do |acc_id, ref_list|
            # DRA accessionに紐づくBioProjectIDを取得(一応リスト)
            bioproject_submission_id_list = ref_list.select{|row| row["ext_acc_type"] == "PSUB"}.map{|row| row["ref_name"]}
            bioproject_accession_id_list = []
            bioproject_submission_id_list.each do |bioproject_submission_id|
              bioproject_accession_id_list.push(get_bioproject_accession(bioproject_submission_id))
            end
            bioproject_accession_id_list.compact!
            # 結果が返ってきたsmp_idに対してproject_id情報を足す
            ref_list.each do |row|
              selected = result.select{|biosample| biosample[:smp_id] == row["ref_name"]}
              selected.each{|ret| ret[:bioproject_accession_id_list] = bioproject_accession_id_list}
            end
          end
        end
      rescue => ex
        message = "Failed to execute the query to DDBJ '#{DRA_DB_NAME}'.\n"
        message += "#{ex.message} (#{ex.class})"
        raise StandardError, message, ex.backtrace
      ensure
        connection.close if connection
      end
    end
    result
  end

  #
  # 指定されたBioSample の smp_id に対する BioProject Accession ID のリストを付与して配列で返す。DRA登録を通して検索する。
  # IDがDBにない場合や、statusが無効な場合にはsmp_idを付与しない
  #
  # ==== Args
  # biosample_smp_id_list ex. ["64274", "00000"]
  # ==== Return
  # smp_idとBioProject Accession IDの配列
  # [ {smp_id: "64274", bioproject_accession_id_list: ["64274"]}, {smp_id: "00000"}]
  #
  def get_run_id_via_dra(biosample_smp_id_list)
    return nil if biosample_smp_id_list.nil?
    result = []
    biosample_smp_id_list.each do |smp_id|
      result.push({smp_id: smp_id})
    end
    if biosample_smp_id_list.size > 0
      begin
        connection = get_connection(DRA_DB_NAME)
        id_place_holder = (1..biosample_smp_id_list.size).map{|idx| "$" + idx.to_s}.join(",")

        q = "SELECT ext_ent.ref_name, drr_ent.acc_type, drr_ent.acc_no, drx_drr_rel.grp_id
              FROM mass.ext_entity ext_ent
              JOIN mass.ext_relation ext_rel USING(ext_id)
              JOIN mass.accession_entity drx_ent ON(ext_rel.acc_id = drx_ent.acc_id)
              JOIN mass.accession_relation drx_drr_rel ON(drx_ent.acc_id = drx_drr_rel.p_acc_id)
              JOIN mass.accession_entity drr_ent ON(drx_drr_rel.acc_id = drr_ent.acc_id)
              JOIN mass.current_dra_submission_group_view g_view ON(drx_drr_rel.grp_id = g_view.grp_id)
             WHERE ext_ent.ref_name IN (#{id_place_holder})
              AND drx_drr_rel.grp_id = ext_rel.grp_id
              AND drr_ent.is_delete != TRUE
              AND g_view.status NOT IN (900, 1000, 1100)"
        connection.prepare("pre_query", q)
        res = connection.exec_prepared("pre_query", biosample_smp_id_list)
        res.each do |row|
          # 結果が返ってきたBioSampleがあればsmp_id情報を足す
          selected = result.select{|biosample| biosample[:smp_id] == row["ref_name"]}
          selected.each do |ret|
            ret[:drr_accession_id_list] = [] if ret[:drr_accession_id_list].nil?
            run_accession_id = "#{row["acc_type"]}#{row["acc_no"].rjust(6, '0')}" # 0埋め6桁
            ret[:drr_accession_id_list].push(run_accession_id)
          end
        end
      rescue => ex
        message = "Failed to execute the query to DDBJ '#{DRA_DB_NAME}'.\n"
        message += "#{ex.message} (#{ex.class})"
        raise StandardError, message, ex.backtrace
      ensure
        connection.close if connection
      end
    end
    result
  end

  #
  # 指定されたBioSample Accession IDに紐づくBioSample Acccession ID のリストと DRR ID のリストを付与して配列で返す
  # 紐づくIDがない場合には各IDリストは空リストを返す
  #
  # ==== Args
  # biosample_accession_list ex. ["SAMD00052344", "SAMD00000000"]
  # ==== Return
  # smp_idとBioProject Accession IDの配列
  # [
  #   { biosample_id: "SAMD00052344", smp_id: "64274", bioproject_accession_id_list: ["PRJDB4841"], drr_accession_id_list: ["DRR060518"] },
  #   { biosample_id: "SAMD00052344", bioproject_accession_id_list: [], drr_accession_id_list: [] }
  # ]
  #
  def get_biosample_related_id(biosample_accession_list)
    return [] if biosample_accession_list.nil?

    biosample_list_with_smp_id = get_valid_smp_id(biosample_accession_list)
    biosample_list_with_smp_id.each{|row|
      row[:bioproject_accession_id_list] = []
      row[:drr_accession_id_list] = []
    }
    smp_id_list = biosample_list_with_smp_id.map{|row| row[:smp_id] }
    project_id_list = get_bioproject_id_via_dra(smp_id_list)
    run_id_list = get_run_id_via_dra(smp_id_list)
    biosample_list_with_smp_id.each do |biosample|
      unless biosample[:smp_id].nil?
        related_project = project_id_list.select{|row| row[:smp_id] == biosample[:smp_id]}
        if related_project.size > 0 && !related_project[0][:bioproject_accession_id_list].nil?
          biosample[:bioproject_accession_id_list] = related_project[0][:bioproject_accession_id_list]
        end
        related_run = run_id_list.select{|row| row[:smp_id] == biosample[:smp_id]}
        if related_run.size > 0 && !related_run[0][:drr_accession_id_list].nil?
          biosample[:drr_accession_id_list] = related_run[0][:drr_accession_id_list]
        end
      end
    end
    biosample_list_with_smp_id
  end

  #
  # 指定されたBioSample Accession IDのうち、submitter_id に紐付く有効なサンプルのリストを返す
  # 紐付くサンプルがなければ空リストを返す
  #
  # ==== Args
  # biosample_accession_list ex. ["SAMD00052344", "SAMD00000000"]
  # submitter_id ""
  # ==== Return
  # 有効なBioProject Accession IDの配列
  # [
  #   { "SAMD00052344", smp_id: "64274", bioproject_accession_id_list: ["PRJDB4841"], drr_accession_id_list: ["DRR060518"] },
  #   { biosample_id: "SAMD00052344", bioproject_accession_id_list: [], drr_accession_id_list: [] }
  # ]
  #
  def get_valid_sample_id_list(biosample_accession_list, submitter_id)
    return [] if biosample_accession_list.nil?
    return [] if submitter_id.nil?

    result = []
    biosample_id_list = []
    biosample_accession_list.each do |biosample_accession|
      if biosample_accession =~ /^SAMD\d+/
        biosample_id_list.push(biosample_accession)
      end
    end
    if biosample_id_list.size > 0
      param_list = [submitter_id].concat(biosample_id_list)
      begin
        connection = get_connection(BIOSAMPLE_DB_NAME)
        id_place_holder = (2..(biosample_id_list.size + 1) ).map{|idx| "$" + idx.to_s}.join(",") # submitter_idが $1 なので $2から
        q = "SELECT accession_id
            FROM mass.sample smp
              JOIN mass.accession acc USING(smp_id)
              JOIN mass.submission USING(submission_id)
            WHERE submitter_id = $1
              AND accession_id IN (#{id_place_holder})
              AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"
        connection.prepare("pre_query", q)
        res = connection.exec_prepared("pre_query", param_list)
        res.each do |row|
          result.push(row["accession_id"])
        end
      rescue => ex
        message = "Failed to execute the query to DDBJ '#{BIOSAMPLE_DB_NAME}'.\n"
        message += "#{ex.message} (#{ex.class})"
        raise StandardError, message, ex.backtrace
      ensure
        connection.close if connection
      end
    end
    result
    
  end
end
