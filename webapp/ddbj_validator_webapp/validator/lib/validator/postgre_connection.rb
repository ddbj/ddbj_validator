require 'pg'
require 'yaml'

config = YAML.load_file("/home/vagrant/ddbj_validator/webapp/db_conf/db_conf.yaml")
#config = YAML.load_file("/Users/oec/Documents/ddbj/ddbj_validator/webapp/db_conf/db_conf.yaml")

# db_user 運用環境のDBのOwner
$pg_user = config["pg_user"]
$pg_port = config["pg_port"]
$pg_host = config["pg_host"]
$pg_bs_db_name = config["pg_bs_name"]
$pg_bp_db_name = config["pg_bp_name"]
$pg_pass = config["pg_pass"]

class GetSubmitterItem
  def getitems(submitter_id)
    begin
      @submitter_id = submitter_id
      #connection = PG::connect(:host => $pg_host, :user => $pg_user, :dbname => $pg_bs_db_name, :port => $pg_port, :password => $pg_pass)
      connection = PGconn.connect($pg_host, $pg_port, '', '',  $pg_bs_db_name, $pg_user,  $pg_pass)

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
      res = {:items => @items, :status => "success"}

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
end

class GetBioProjectItem
  def get_submitter(bioproject_id)
    begin
      #connection = PG::connect(:host => $pg_host, :user => $pg_user, :dbname => $pg_bp_db_name, :port => $pg_port, :password => $pg_pass)
      connection = PGconn.connect($pg_host, $pg_port, '', '',  $pg_bp_db_name, $pg_user,  $pg_pass)

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
        prjd_query_id = bioproject_id.gsub("PRJDB", "").to_i

        q = "SELECT 'PRJDB' || p.project_id_counter prjd, x.submission_id, p.status_id, sub.submitter_id
       FROM mass.project p
       LEFT OUTER JOIN mass.xml x USING(submission_id)
       LEFT OUTER JOIN mass.submission sub USING(submission_id)
       WHERE p.project_id_counter = #{prjd_query_id} AND (x.submission_id, x.version) IN (SELECT submission_id, MAX(version) from mass.xml
       GROUP BY submission_id)
       ORDER BY submission_id"

      end

      resp = connection.exec(q)
      @items = []
      resp.each {|item|
        @items.push(item)
      }
      res = {:items => @items, :status => "success"}

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

end

class IsUmbrellaId
  def is_umbrella(bioproject_id)

    begin
      #connection = PG::connect(:host => $pg_host, :user => $pg_user, :dbname => $pg_bp_db_name, :port => $pg_port, :password => $pg_pass)
      connection = PGconn.connect($pg_host, $pg_port, '', '',  $pg_bp_db_name, $pg_user,  $pg_pass)

      q = "SELECT COUNT(*)
          FROM mass.umbrella_info u
          WHERE u.parent_submission_id = '#{bioproject_id}'"

      response = connection.exec(q)

      # if "count" >= 1 this bioproject_id is  umbrella id
      @count = response[0]["count"].to_s
      res = {:items => @count, :status => "success"}

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
end

class GetSampleNames
  def getnames(submission_id)
    begin
      #connection = PG::connect(:host => $pg_host, :user => $pg_user, :dbname => $pg_bs_db_name, :port => $pg_port, :password => $pg_pass)
      connection = PGconn.connect($pg_host, $pg_port, '', '',  $pg_bs_db_name, $pg_user,  $pg_pass)

      q1 = "SELECT smpl.sample_name, attr.attribute_value
      From mass.sample smpl, mass.attribute attr
      WHERE smpl.submission_id = '#{submission_id}'
      AND attr.attribute_name = 'sample_title'
      AND attr.smp_id = smpl.smp_id"

      result = connection.exec(q1)
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
end

class GetPRJDBId
  def get_id(psub_id)
    begin
      #connection = PG::connect(:host => $pg_host, :user => $pg_user, :dbname => $pg_bp_db_name, :port => $pg_port, :password => $pg_pass)
      connection = PGconn.connect($pg_host, $pg_port, '', '',  $pg_bp_db_name, $pg_user,  $pg_pass)

      q = "SELECT p.project_id_counter prjd, p.project_id_prefix
    FROM mass.project p
    WHERE p.submission_id = '#{psub_id}'"

      res = connection.exec(q)

      @items = []
      res.each {|item|
        @items.push(item)
      }
      res = {:items => @items, :status => "success"}

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
end

class GetLocusTagPrefix
  def unique_prefix?(prefix, submission_id)
    begin
      #connection = PG::connect(:host => $pg_host, :user => $pg_user, :dbname => $pg_bs_db_name, :port => $pg_port, :password => $pg_pass)
      connection = PGconn.connect($pg_host, $pg_port, '', '',  $pg_bs_db_name, $pg_user,  $pg_pass)

      q0 = "SELECT a.attribute_name, a.attribute_value, a.smp_id, s.submission_id
    FROM mass.attribute a, mass.sample s
    WHERE s.submission_id = '#{submission_id}' AND a.smp_id = s.smp_id AND attribute_name = 'locus_tag_prefix'"

      q1 = "SELECT a.attribute_name, a.attribute_value
    FROM mass.attribute a
    WHERE a.attribute_name  = 'locus_tag_prefix'"

      res0 = connection.exec(q0)
      res1 = connection.exec(q1)

      @own_items= []
      res0.each do |item|
        unless item["attribute_value"].empty?
          @own_items.push(item["attribute_value"])
        end
      end

      @items = []
      res1.each do |item|
        unless item["attribute_value"].empty?
          @items.push(item["attribute_value"])
        end
      end
      @item_oters =  @items - @own_items
      @item_oters.include?(prefix) ? result = false : result = true
      res = {:items => result, :status => "success"}

    rescue PG::Error => ex
      res = {:message => ex.message, :status => "error"}
    rescue => ex
      res = {:message => ex.message, :status => "error"}
    ensure
      connection.close if connection
    end

  end
end