#
# A class for validation
#
class CombinationValidator < ValidatorBase
  attr_reader :error_list

  #
  # Initializer
  #
  def initialize
    super
    @conf.merge!(read_config(File.absolute_path(File.dirname(__FILE__) + '/../../conf/dra')))

    @error_list = error_list = []

    @validation_config = @conf[:validation_config] # need?
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
      config[:validation_config] = JSON.parse(File.read(config_file_dir + '/rule_config_dra.json')) # TODO auto update when genereted
      config[:platform_filetype] = JSON.parse(File.read(config_file_dir + '/platform_filetype.json'))
      config
    rescue => ex
      message = "Failed to parse the setting file. Please check the config file below.\n"
      message += "#{ex.message} (#{ex.class})"
      raise StandardError, message, ex.backtrace
    end
  end

  #
  # Validate the all rules for combination data.
  # Error/warning list is stored to @error_list
  #
  # ==== Args
  # data_xml: xml file path
  #
  #
  def validate (data)
    unless data[:biosample].nil?
      @biosample_data_file = File.basename(data[:biosample])
      @biosample_doc = Nokogiri::XML(File.read(data[:biosample]))
    end
    unless data[:bioproject].nil?
      @bioproject_data_file = File.basename(data[:bioproject])
      @bioproject_doc = Nokogiri::XML(File.read(data[:bioproject]))
    end
    unless data[:submission].nil?
      @submission_data_file = File.basename(data[:submission])
      @submission_doc = Nokogiri::XML(File.read(data[:submission]))
    end
    unless data[:experiment].nil?
      @experiment_data_file = File.basename(data[:experiment])
      @experiment_doc = Nokogiri::XML(File.read(data[:experiment]))
    end
    unless data[:run].nil?
      @run_data_file = File.basename(data[:run])
      @run_doc = Nokogiri::XML(File.read(data[:run]))
    end
    unless data[:analysis].nil?
      @analysis_data_file = File.basename(data[:analysis])
      @analysis_doc = Nokogiri::XML(File.read(data[:analysis]))
    end
    multiple_bioprojects_in_a_submission('DRA_R0003', @experiment_doc, @analysis_doc)
    if !(data[:experiment].nil? || data[:run].nil?)
      experiment_not_found('DRA_R0017', @experiment_doc, @run_doc)
      one_fastq_file_for_paired_library('DRA_R0027', @experiment_doc, @run_doc)
      invalid_PacBio_RS_II_hdf_file_series('DRA_R0028', @experiment_doc, @run_doc)
      invalid_filetype('DRA_R0030', @experiment_doc, @run_doc)
    end
  end

  # TODO get object rabel and insert to error message

  ### validate method ###

  #
  # rule: DRA_R0003
  # 1 submission 中の Experiment と Analysis から参照されている BioProject が一つではない場合エラー
  #
  # ==== Args
  # experiment_set:
  # analysis_set:
  # ==== Return
  # true/false
  #
  def multiple_bioprojects_in_a_submission (rule_code, experiment_set, analysis_set)
    # accession 属性がない場合には空文字として扱い記述もれを検知する
    collect_refs = ->(set, xpath) {
      return [] if set.nil?
      set.xpath(xpath).map {|node|
        node_blank?(node, 'STUDY_REF/@accession') ? '' : get_node_text(node, 'STUDY_REF/@accession')
      }
    }
    ref_project_list = collect_refs.call(experiment_set, '//EXPERIMENT') + collect_refs.call(analysis_set, '//ANALYSIS')
    return true if ref_project_list.uniq.size <= 1

    annotation = [
      {key: 'STUDY_REF', value: ref_project_list.to_s},
      {key: 'Path',      value: '//EXPERIMENT/STUDY_REF/@accession, //ANALYSIS/STUDY_REF/@accession'}
    ]
    add_error(rule_code, annotation)
    false
  end

  #
  # rule: DRA_R0017
  # Run からの Experiment 参照が同一 submission 内に存在しているか
  #
  # ==== Args
  # experiment_set:
  # run_set:
  # ==== Return
  # true/false
  #
  def experiment_not_found (rule_code, experiment_set, run_set)
    experiment_alias_list = experiment_set.xpath('//EXPERIMENT').reject { node_blank?(it, '@alias') }
                                          .map { get_node_text(it, '@alias') }
    refname_path = 'EXPERIMENT_REF/@refname'

    missing = run_set.xpath('//RUN').each_with_index.filter_map {|run_node, idx|
      next if node_blank?(run_node, refname_path)
      refname = get_node_text(run_node, refname_path)
      next if experiment_alias_list.include?(refname)

      [refname, idx + 1]
    }
    return true if missing.empty?

    missing.each do |refname, run_idx|
      annotation = [
        {key: 'refname', value: refname},
        {key: 'Path',    value: "//RUN[#{run_idx}]/#{refname_path}"}
      ]
      add_error(rule_code, annotation)
    end
    false
  end

  #
  # rule: DRA_R0027
  # run が参照している experiment の library layout が paired の場合、
  # 当該 run 中の filetype="fastq" もしくは generic_fastq であるファイルの数が 1 の場合ワーニング
  #
  # ==== Args
  # experiment_set:
  # run_set:
  # ==== Return
  # true/false
  #
  def one_fastq_file_for_paired_library (rule_code, experiment_set, run_set)
    refname_path = 'EXPERIMENT_REF/@refname'
    bad = run_set.xpath('//RUN').each_with_index.filter_map {|run_node, idx|
      next if node_blank?(run_node, refname_path)
      refname = get_node_text(run_node, refname_path)

      paired = experiment_set.xpath("//EXPERIMENT[@alias='#{refname}']").any? {
        !it.xpath('DESIGN/LIBRARY_DESCRIPTOR/LIBRARY_LAYOUT/PAIRED').empty?
      }
      next unless paired

      # fastq または generic_fastq のファイルが 1 つしかなければ NG
      single_fastq = run_node.xpath("DATA_BLOCK/FILES/FILE[@filetype='fastq']").size == 1 ||
                     run_node.xpath("DATA_BLOCK/FILES/FILE[@filetype='generic_fastq']").size == 1
      next unless single_fastq

      [refname, idx + 1]
    }
    return true if bad.empty?

    bad.each do |refname, run_idx|
      annotation = [
        {key: 'refname', value: refname},
        {key: 'Path',    value: "//RUN[#{run_idx}]/DATA_BLOCK/FILES/FILE"}
      ]
      add_error(rule_code, annotation)
    end
    false
  end

  #
  # rule: DRA_R0028
  # Instrument が PacBio RS II で filetype="hdf5" がある場合、1 Run あたり 1 bas、3 bax で同一シリーズ由来か
  #
  # ==== Args
  # experiment_set:
  # run_set:
  # ==== Return
  # true/false
  #
  def invalid_PacBio_RS_II_hdf_file_series (rule_code, experiment_set, run_set)
    pacbio_aliases = experiment_set.xpath('//EXPERIMENT[@alias]')
                                   .select { get_node_text(it, 'PLATFORM/PACBIO_SMRT/INSTRUMENT_MODEL') == 'PacBio RS II' }
                                   .map { get_node_text(it, '@alias') }

    bad = run_set.xpath('//RUN').each_with_index.filter_map {|run_node, idx|
      refname = pacbio_aliases.find { !run_node.xpath("EXPERIMENT_REF[@refname='#{it}']").empty? }
      next unless refname

      filenames = run_node.xpath('DATA_BLOCK/FILES/FILE').map { get_node_text(it, '@filename') }
      # filename で *bax.h5 が 3 ファイル, *bas.h5 が 1 ファイルでないと NG
      next if filenames.count { it =~ /bax.h5$/ } == 3 && filenames.count { it =~ /bas.h5$/ } == 1

      [refname, idx]
    }
    return true if bad.empty?

    bad.each do |refname, run_idx|
      annotation = [
        {key: 'refname', value: refname},
        {key: 'Path',    value: "//RUN[#{run_idx}]/DATA_BLOCK/FILES/FILE"}
      ]
      add_error(rule_code, annotation)
    end
    false
  end

  #
  # rule: DRA_R0030
  # Platform名とfiletypeの組み合わせが正しいか
  #
  # ==== Args
  # experiment_set:
  # run_set:
  # ==== Return
  # true/false
  #
  def invalid_filetype (rule_code, experiment_set, run_set)
    bad = experiment_set.xpath('//EXPERIMENT[@alias]').flat_map {|ex_node|
      platform_name = ex_node.xpath('PLATFORM/*[position() = 1]').first&.name # PLATFORMの最初の子要素名
      next [] if platform_name.nil?

      platform_setting = @conf[:platform_filetype].find { it['platform'] == platform_name }
      next [] if platform_setting.nil?

      accept_filetype_list = platform_setting['filetype']
      refname = get_node_text(ex_node, '@alias')

      run_set.xpath('//RUN').each_with_index.filter_map {|run_node, idx|
        next if run_node.xpath("EXPERIMENT_REF[@refname='#{refname}']").empty?

        filetype_list = run_node.xpath('DATA_BLOCK/FILES/FILE').map { get_node_text(it, '@filetype') }
        # 記載された filetype のリストから許容された filetype を除き、他があれば NG
        unaccept = filetype_list - accept_filetype_list
        next if unaccept.empty?

        [refname, platform_name, unaccept.uniq, idx]
      }
    }
    return true if bad.empty?

    bad.each do |refname, platform_name, unaccept, run_idx|
      annotation = [
        {key: 'refname',  value: refname},
        {key: 'platform', value: platform_name},
        {key: 'filetype', value: unaccept.to_s},
        {key: 'Path',     value: "//RUN[#{run_idx}]/DATA_BLOCK/FILES/FILE"}
      ]
      add_error(rule_code, annotation)
    end
    false
  end
end
