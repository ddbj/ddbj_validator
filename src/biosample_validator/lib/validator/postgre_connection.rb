require 'pg'

# PostgreSQL接続の設定
$pg_user = "oec"
$pg_port = "5432"
$pg_host = "localhost"
$pg_bs_db_name = "bstest"
$pg_bp_db_name = "bptest"
# $pg_pass = ""

class GetSubmitterItem
  def getitems(submitter_id)
    begin
      @submitter_id = submitter_id
      connection = PG::connect(:host => $pg_host, :user => $pg_user, :dbname => $pg_bs_db_name, :port => $pg_port)

      q = "SELECT form.submission_id, attribute_name, attribute_value, submitter_id
        FROM mass.attribute attr, mass.submission_form form, mass.sample sample
        WHERE form.submitter_id = '#{@submitter_id}' AND sample.submission_id = form.submission_id
          AND attr.smp_id = sample.smp_id
          AND attr.attribute_name = 'sample_title'"

      res = connection.exec(q)
      @items = []
      res.each do |item|
        @items.push(item["attribute_value"])
      end
      @items

      rescue PG::Error => ex
        @items = nil
      rescue => ex
        @items = nil
      ensure
        connection.close if connection
    end
  end
end

class GetBioProjectItem
  def get_submitter(bioproject_id)
    begin
      connection = PG::connect(:host => $pg_host, :user => $pg_user, :dbname => $pg_bp_db_name, :port => $pg_port)

      # PSUB
      if bioproject_id =~ /^PSUB\d{6}/
        psub_query_id = bioproject_id

        q = "SELECT 'PRJDB' || p.project_id_counter prjd, x.submission_id, p.status_id, sub.submitter_id
        FROM mass.project p
        LEFT OUTER JOIN mass.xml x USING(submission_id)
        LEFT OUTER JOIN mass.submission sub USING(submission_id)
        WHERE x.submission_id = '#{psub_query_id}'  AND (x.submission_id, x.version) IN (SELECT submission_id, MAX(version) from mass.xml
        GROUP BY submission_id)
        ORDER BY submission_id"

      # PRJDB
      elsif bioproject_id =~ /^PRJDB\d+/
        bp = bp.sub("PRJDB", "").to_i
        prjd_query_id_a = bp

        q = "SELECT 'PRJDB' || p.project_id_counter prjd, x.submission_id, p.status_id, sub.submitter_id
       FROM mass.project p
       LEFT OUTER JOIN mass.xml x USING(submission_id)
       LEFT OUTER JOIN mass.submission sub USING(submission_id)
       WHERE p.project_id_counter = #{prjd_query_id} AND (x.submission_id, x.version) IN (SELECT submission_id, MAX(version) from mass.xml
       GROUP BY submission_id)
       ORDER BY submission_id"

      end

      res = connection.exec(q)
      @items = []
      res.each {|item|
        @items.push(item)
      }

      @items

    rescue PG::Error => ex
      #p ex.class, ex.message
      @itemts = []

    rescue => ex
      #p ex.class, ex.message
      @items = []

    ensure
      connection.close if connection

    end
  end

end

class IsUmbrellaId
  def is_umnrella(bioproject_id)

    begin
      connection = PG::connect(:host => $pg_host, :user => $pg_user, :dbname => $pg_bp_db_name, :port => $pg_port)

      q = "SELECT COUNT(*)
          FROM mass.umbrella_info u
          WHERE u.parent_submission_id = '#{bioproject_id}'"

      res = connection.exec(q)

      results = res[0]["count"]

    rescue PG::Error => ex
      #p ex.class, ex.message
      resulst = nil

    rescue => ex
      #p ex.class, ex.message
      result = nil

    ensure
      connection.close if connection
    end
  result
  end
end

class GetSampleNames
  def getnames(submission_id)
    begin
      connection = PG::connect(:host => $pg_host, :user => $pg_user, :dbname => $pg_bs_db_name, :port => $pg_port)

      q = "SELECT bs.sample_name
        FROM mass.biosample_summary bs
        WHERE bs.submission_id = '#{submission_id}'"

      result = connection.exec(q)

    rescue PG::Error => ex
      #p ex.class, ex.message
      resulst = nil

    rescue => ex
      #p ex.class, ex.message
      result = nil

    ensure
      connection.close if connection
    end

  end
end

class GetPRJDBId
  def get_id(psub_id)
    connection = PG::connect(:host => $pg_host, :user => $pg_user, :dbname => $pg_db_name, :port => $pg_port)

    begin

      q = "SELECT p.project_id_counter prjd, p.project_id_prefix
    FROM mass.project p
    WHERE p.submission_id = '#{psub_id}'"

      res = connection.exec(q)

      @items = []
      res.each {|item|
        @items.push(item)
      }

      @items

    rescue PG::Error => ex
      p ex.class, ex.message
      @itemts = nil

    rescue => ex
      p ex.class, ex.message
      @items = nil

    ensure
      connection.close if connection

    end

  end
end