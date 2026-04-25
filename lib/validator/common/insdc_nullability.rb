require 'active_support/core_ext/object/blank'

# INSDC で null 相当の表現 ("missing: control sample", "not applicable", "NA" 等) を
# 判定するユーティリティ。`conf/biosample/null_accepted.json` と
# `conf/biosample/null_not_recommended.json` をクラスロード時に一度だけ読み込み、
# frozen 配列で保持する (起動後は read-only なので thread safe)。
module InsdcNullability
  CONF_DIR             = Rails.root.join('conf/biosample').freeze
  NULL_ACCEPTED        = JSON.parse(File.read(CONF_DIR.join('null_accepted.json'))).freeze
  NULL_NOT_RECOMMENDED = JSON.parse(File.read(CONF_DIR.join('null_not_recommended.json'))).freeze

  #
  # nil, 空白, "missing: ...", "not applicable" など null 定義に該当するなら true。
  #
  def self.null_value?(value)
    return true if value.blank?

    NULL_ACCEPTED.any? { value =~ /^(#{it})$/i }
  end

  #
  # "NA" (case insensitive) 等、推奨されない null 表現なら true。
  #
  def self.null_not_recommended_value?(value)
    return false if value.blank?

    NULL_NOT_RECOMMENDED.any? { value =~ /^(#{it})$/i }
  end

  #
  # null 表現に該当、または null 表現を除去した後に意味のある単語
  # (英数字2文字以上) が残らなければ true。
  # allow_reporting_term=true の場合は "missing: ..." を許容する。
  #
  def self.meaningless_value?(value, allow_reporting_term = false)
    return false if value.blank?
    return true  if NULL_NOT_RECOMMENDED.any? { value =~ /^(#{it})$/i }

    accepted = allow_reporting_term ? NULL_ACCEPTED.reject { it.start_with?('missing:') } : NULL_ACCEPTED
    return true if accepted.any? { value =~ /^(#{it})$/i }

    stripped = (accepted + NULL_NOT_RECOMMENDED).inject(value) {|s, n| s.gsub(/#{n}/i, '') }
    stripped.split(' ').none? { it.scan(/[0-9a-zA-Z]/).length >= 2 }
  end
end
