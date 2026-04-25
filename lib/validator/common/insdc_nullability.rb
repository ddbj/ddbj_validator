require 'active_support/core_ext/object/blank'

# INSDC で null 相当の表現 ("missing: control sample", "not applicable", "NA" 等) を
# 判定するユーティリティ。設定ファイル (null_accepted.json / null_not_recommended.json)
# から正規表現リストが与えられる。
#
# 各 validator が `null_accepted` / `null_not_recommended` を引数にインスタンスを生成する。
# 過去は module + class-accessor だったが、validator 種別ごとに list が違うため
# thread safety を確保すべくインスタンス state に移した。
class InsdcNullability
  def initialize(null_accepted:, null_not_recommended:)
    @null_accepted = null_accepted
    @null_not_recommended = null_not_recommended
  end

  #
  # nil, 空白, "missing: ...", "not applicable" など null 定義に該当するなら true。
  #
  def null_value?(value)
    return true if value.blank?

    @null_accepted.any? { value =~ /^(#{it})$/i }
  end

  #
  # "NA" (case insensitive) 等、推奨されない null 表現なら true。
  #
  def null_not_recommended_value?(value)
    return false if value.blank?

    @null_not_recommended.any? { value =~ /^(#{it})$/i }
  end

  #
  # null 表現に該当、または null 表現を除去した後に意味のある単語
  # (英数字2文字以上) が残らなければ true。
  # allow_reporting_term=true の場合は "missing: ..." を許容する。
  #
  def meaningless_value?(value, allow_reporting_term = false)
    return false if value.blank?
    return true  if @null_not_recommended.any? { value =~ /^(#{it})$/i }

    accepted = allow_reporting_term ? @null_accepted.reject { it.start_with?('missing:') } : @null_accepted
    return true if accepted.any? { value =~ /^(#{it})$/i }

    stripped = (accepted + @null_not_recommended).inject(value) {|s, n| s.gsub(/#{n}/i, '') }
    stripped.split(' ').none? { it.scan(/[0-9a-zA-Z]/).length >= 2 }
  end
end
