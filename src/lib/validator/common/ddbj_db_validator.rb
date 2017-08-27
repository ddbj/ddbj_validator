require 'pg'
require 'yaml'

class DDBJDbValidator
  BIOPROJCT_DB_NAME = "bioproject"
  BIOSAMPLE_DB_NAME = "biosample"
  SUBMITTER_DB_NAME = "submitterdb"

  def initialize (config)
    @pg_host = config["pg_host"]
    @pg_port = config["pg_port"]
    @pg_user = config["pg_user"]
    @pg_pass = config["pg_pass"]
  end

  #
  # 指定されたBioSample Accession IDのsubmitter_idを返す
  # DBにない場合にはnilを返す
  #
  # ==== Args
  # bioproject_acceccion ex. "PSUB004142", "PRJDB3490"
  # ==== Return
  # BioProjectのIDとsubmitter情報のハッシュ
  # {
  #   "bioproject_accession" => "PRJDB3490",
  #   "submission_id" => "PSUB004142",
  #   "submitter_id" => "test01"
  # }
  def get_bioproject_submitter_id(bioproject_accession)
    return nil if bioproject_accession.nil?
    result = nil
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', BIOPROJCT_DB_NAME, @pg_user,  @pg_pass)

      if bioproject_accession =~ /^PSUB\d{6}/
        psub_query_id = bioproject_accession

        q = "SELECT p.project_id_prefix || p.project_id_counter bioproject_accession, sub.submission_id, sub.submitter_id 
             FROM mass.submission sub 
              LEFT OUTER JOIN mass.project p USING(submission_id)
             WHERE sub.submission_id = '#{psub_query_id}'
               AND (p.status_id IS NULL OR p.status_id NOT IN (5600, 5700))"
      elsif bioproject_accession =~ /^PRJDB\d+/
        prjd_query_id = bioproject_accession.gsub("PRJDB", "").to_i

        q = "SELECT p.project_id_prefix || p.project_id_counter bioproject_accession, sub.submission_id, sub.submitter_id 
             FROM mass.submission sub 
              LEFT OUTER JOIN mass.project p USING(submission_id)
             WHERE p.project_id_counter = #{prjd_query_id} 
              AND (p.status_id IS NULL OR p.status_id NOT IN (5600, 5700))"
      else
        return nil
      end

      res = connection.exec(q)
      if 1 == res.ntuples then
        result = res[0]
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
             WHERE p.submission_id = '#{psub_query_id}'
              AND p.project_type = 'umbrella'
              AND (p.status_id IS NULL OR p.status_id NOT IN (5600, 5700))"
      elsif bioproject_accession =~ /^PRJDB\d+/
        prjd_query_id = bioproject_accession.gsub("PRJDB", "").to_i

        q = "SELECT COUNT(*)
             FROM mass.project p 
             WHERE p.project_id_counter = #{prjd_query_id} 
              AND p.project_type = 'umbrella'
              AND (p.status_id IS NULL OR p.status_id NOT IN (5600, 5700))"
      else
        return false
      end

      res = connection.exec(q)
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
            WHERE smp.submission_id = '#{submission_id}'
              AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"

      res = connection.exec(q)
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
           WHERE p.submission_id = '#{psub_id}'
            AND p.project_id_counter IS NOT NULL
            AND p.project_id_prefix IS NOT NULL
            AND (p.status_id IS NULL OR p.status_id NOT IN (5600, 5700))"

      res = connection.exec(q)
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
  # biosample databaseに存在するlocus_tag_prefixを取得してリストで返す
  #
  # ==== Args
  # ==== Return
  # locus_tag_prefixのリスト。一つもない場合にも空のリストを返す
  # [ "XXC","XXA", ...]
  #
  def get_all_locus_tag_prefix
    prefix_list = []
    begin
      connection = PG::Connection.connect(@pg_host, @pg_port, '', '', BIOSAMPLE_DB_NAME, @pg_user,  @pg_pass)

      q = "SELECT attr.attribute_value
           FROM mass.attribute attr
            JOIN mass.sample smp USING (smp_id)
           WHERE attribute_name = 'locus_tag_prefix' AND attribute_value <> ''
            AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"

      res = connection.exec(q)

      res.each do |item|
        unless item["attribute_value"].empty?
          prefix_list.push(item["attribute_value"])
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
               AND smp.submission_id = '#{ssub_query_id}'
               AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"
      elsif biosample_accession =~ /^SAMD\d+/
        samd_query_id = biosample_accession

        q = "SELECT attr.attribute_value AS locus_tag_prefix, acc.accession_id, smp.submission_id
             FROM mass.sample smp
               LEFT OUTER JOIN mass.accession acc USING(smp_id)
               JOIN mass.attribute attr USING(smp_id)
             WHERE attr.attribute_name = 'locus_tag_prefix'
               AND attr.attribute_value != ''
               AND acc.accession_id = '#{samd_query_id}'
               AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"
      else
        return nil
      end

      res = connection.exec(q)
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
             WHERE smp.submission_id = '#{ssub_query_id}'
               AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"
      elsif biosample_accession =~ /^SAMD\d+/
        samd_query_id = biosample_accession

        q = "SELECT DISTINCT sub.submitter_id, acc.accession_id, sub.submission_id
             FROM mass.sample smp
               LEFT OUTER JOIN mass.accession acc USING(smp_id)
               LEFT OUTER JOIN mass.submission sub USING(submission_id)
             WHERE acc.accession_id = '#{samd_query_id}'
               AND (smp.status_id IS NULL OR smp.status_id NOT IN (5600, 5700))"
      else
        return nil
      end

      res = connection.exec(q)
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

      q = "SELECT submitter_id, center_name, organization, department, affiliation, unit FROM mass.organization WHERE submitter_id = '#{submitter_id}'"

      res = connection.exec(q)
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

      q = "SELECT submitter_id, email, first_name, middle_name, last_name FROM mass.contact WHERE submitter_id = '#{submitter_id}' and is_contact = true"

      res = connection.exec(q)
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
