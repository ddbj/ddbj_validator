require 'http'

# NCBI E-utilities (esummary) と DBCLS tm medline に対する「この ID 実在する?」確認用
# クライアント。PubMed ID と PMC ID の存在確認に使う。
#
# API key は process-wide で 1 つ。validator 起動時 (ValidatorBase#read_common_config) に
# `NcbiEutils.api_key = ...` で設定されたものを使い回す。
module NcbiEutils
  class << self
    # NCBI eutils API key の文字列 (validator.yml の eutils_api_key.key)。
    attr_accessor :api_key
  end

  EUTILS_SUMMARY_URL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi"
  DBCLS_MEDLINE_URL  = "http://tm.dbcls.jp/medline"

  #
  # 引数の PubMed ID が実在するかを DBCLS/medline 経由で確認する。
  # 数字でない文字列には false、nil には nil。
  #
  def self.exist_pubmed_id? (pubmed_id)
    return nil if pubmed_id.nil?
    return false unless pubmed_id.to_s.strip.chomp =~ /^[0-9]+$/
    exist_in_medline?(pubmed_id.to_s.strip.chomp)
  end

  #
  # 引数の PMC ID が実在するかを NCBI eutils 経由で確認する。
  #
  def self.exist_pmc_id? (pmc_id)
    return nil if pmc_id.nil?
    eutils_summary("pmc", pmc_id)
  end

  #
  # DBCLS tm medline を叩いて PubMed ID の存在確認をする。
  # 該当 ID が無いときは MedlineCitationSet が空で返る。
  #
  def self.exist_in_medline? (pubmed_id)
    return nil if pubmed_id.nil?
    url = "#{DBCLS_MEDLINE_URL}/#{pubmed_id}.json"
    res = HTTP.get(url)
    raise "'tm.dbcls.jp/medline' returns a server error. url: #{url}\n" if res.status.server_error?
    raise "'tm.dbcls.jp/medline' returns an error. url: #{url}\n"       if res.status.client_error?

    entry = res.parse(:json)
    !entry["MedlineCitationSet"].nil? && !entry["MedlineCitationSet"].keys.empty?
  rescue JSON::ParserError
    raise "Parse error: 'tm.dbcls.jp/medline' might not return JSON. url: #{url}\n body: #{res&.body}\n"
  rescue => ex
    raise StandardError, "Connection to 'tm.dbcls.jp/medline' failed. url: #{url}\n", ex.backtrace
  end

  #
  # NCBI eutils esummary を叩いて DB (pubmed / pmc) の ID 存在確認をする。
  # 0.4s sleep で per-second 制約 (10/s, 4 worker で 2.5/s) を守る。
  # https://support.ncbi.nlm.nih.gov/link/portal/28045/28049/Article/2039/Why-and-how-should-I-get-an-API-key-to-use-the-E-utilities
  #
  def self.eutils_summary (db_name, id)
    return nil if db_name.nil? || id.nil?
    sleep(0.4)
    url = "#{EUTILS_SUMMARY_URL}?db=#{db_name}&id=#{id}&retmode=json&api_key=#{api_key}"
    res = HTTP.get(url)
    raise "'NCBI eutils' returns a server error. url: #{url}\n" if res.status.server_error?
    raise "'NCBI eutils' returns an error. url: #{url}\n"       if res.status.client_error?

    entry = res.parse(:json)
    # responseデータに error キーがなければ存在する ID
    !entry["result"].nil? && !entry["result"][id].nil? && entry["result"][id]["error"].nil?
  rescue JSON::ParserError
    raise "Parse error: 'NCBI eutils' might not return JSON. url: #{url}\n body: #{res&.body}\n"
  rescue => ex
    raise StandardError, "Connection to 'NCBI eutils' failed. url: #{url}\n", ex.backtrace
  end
end
