require 'pg'
require 'yaml'

class DDBJDbValidator
  BIOPROJCT_DB_NAME = "bioproject"
  BIOSAMPLE_DB_NAME = "biosample"

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
      connection = PGconn.connect(@pg_host, @pg_port, '', '', BIOPROJCT_DB_NAME, @pg_user,  @pg_pass)

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
      connection = PGconn.connect(@pg_host, @pg_port, '', '', BIOPROJCT_DB_NAME, @pg_user,  @pg_pass)

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

  def get_sample_names (submission_id)
    begin
      connection = PGconn.connect(@pg_host, @pg_port, '', '', BIOSAMPLE_DB_NAME, @pg_user,  @pg_pass)

      q1 = "SELECT smpl.sample_name, attr.attribute_value
      From mass.sample smpl, mass.attribute attr
      WHERE smpl.submission_id = '#{submission_id}'
      AND attr.attribute_name = 'sample_title'
      AND attr.smp_id = smpl.smp_id"

      result = connection.exec(q1)
      #TODO PG::Resultオブジェクトのまま返さない
      res = {:items => result, :status => "success"}

    rescue PG::Error => ex
      @error_message = ex.message.to_s
      res = {:message => @error_message, :status => "error"}

    rescue => ex
      @error_message = ex.message.to_s
      res = {:message => @error_message, :status => "error"}

    ensure
      connection.close if connection
    end
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
      connection = PGconn.connect(@pg_host, @pg_port, '', '', BIOPROJCT_DB_NAME, @pg_user,  @pg_pass)
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
      connection = PGconn.connect(@pg_host, @pg_port, '', '', BIOSAMPLE_DB_NAME, @pg_user,  @pg_pass)

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

end
