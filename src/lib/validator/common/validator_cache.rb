
class ValidatorCache

  EXIST_HOST_NAME = "exist_host_name"
  EXIST_ORGANISM_NAME = "exist_organism_name"
  PACKAGE_ATTRIBUTES = "package_attributes"
  PACKAGE_ATTRIBUTE_GROUPS = "package_attribute_groups"
  UNKNOWN_PACKAGE = "unknown_package"
  COUNTRY_FROM_LATLON = "country_from_latlon"
  EXIST_PUBCHEM_ID = "exist_pubchem_id"
  TAX_VS_PACKAGE = "tax_vs_package"
  TAX_MATCH_ORGANISM = "tax_match_organism"
  TAX_HAS_LINAGE = "tax_has_linage"
  SUBMITTERS_SAMPLE_TITLE = "submitters_sample_title"
  BIOPROJECT_SUBMITTER = "bioproject_submitter"
  SUBMISSIONS_SAMPLE_NAME = "submissions_sample_name"
  IS_UMBRELLA_ID = "is_umbrella_id"
  BIOPROJECT_PRJD_ID = "bioproject_prjd_id"
  LOCUS_TAG_PREFIX = "locus_tag_prefix"

  #
  # Initializer
  #
  def initialize
    @cache_data = {}
  end

  #
  # キャッシュされたキーがあればtrue,なければfalseを返す
  #
  def has_key (cache_name, key)
    if @cache_data[cache_name].nil? || !@cache_data[cache_name].has_key?(key)
      false
    else
      true
    end
  end

  #
  # キャッシュされた値があればその値を、なければnilを返す
  # キャッシュ値自体がnilである場合にもnilで返すため、その可能性があるのであればhas_keyで事前に検査する必要がある
  #
  def check (cache_name, key)
    if @cache_data[cache_name].nil? || @cache_data[cache_name][key].nil?
      nil
    else
      @cache_data[cache_name][key]
    end
  end

  #
  # 値をキャッシュする
  #
  def save (cache_name, key, value)
    @cache_data[cache_name] = {} if @cache_data[cache_name].nil?
    @cache_data[cache_name][key] = value
  end

  #
  # 引数の値でキャッシュのキーを生成する
  # 引数の文字列を"_"で繋いだものを返す
  #
  def self.create_key (*params)
    params.map {|param|
      param.to_s
    }.join("_")
  end

end
