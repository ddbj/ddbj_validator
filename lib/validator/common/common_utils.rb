require 'date'
require 'active_support/core_ext/integer/inflections'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/filters'

class CommonUtils
  def self.set_config (config_obj)
    @@null_accepted = config_obj[:null_accepted]
    @@null_not_recommended = config_obj[:null_not_recommended]
  end


  #
  # 引数がValidatorで値なしとみなされる値であればtrueを返す。
  # nil, 空白文字, 値なしを意味するや"missing: control sample"であればtrueを返す
  #
  # ==== Args
  # value: 検査する値
  # ==== Return
  # true/false
  #
  def self.null_value?(value)
    if value.nil? || value.to_s.strip.empty?
      true
    elsif @@null_accepted.select {|refexp| value =~ /^(#{refexp})$/i }.any?
      true
    else
      false
    end
  end

  #
  # 引数がValidatorで推奨されないnull値とみなされる値であればtrueを返す。
  # "na"や(大文字小文字区別せず)であればtrueを返す
  #
  # ==== Args
  # value: 検査する値
  # ==== Return
  # true/false
  #
  def self.null_not_recommended_value?(value)
    ret = false
    if !(value.nil? || value.strip.empty?)
      if @@null_not_recommended.select {|refexp| value =~ /^(#{refexp})$/i }.any? # null_not_recommendedの正規表現リストにマッチすればNG
        ret = true
      end
    end
    ret
  end

  #
  # 引数が意味のない値であるとみなした場合にtrueを返す。
  # "NA"や"not applicable", "missing"といったnull値定義の値である場合はtrueとする。
  # また、それらの単語を除いた後に残る文字列に英数字が2文字以上ある単語が含まれていなければtrueとする("missing:", "missing: not collected")
  #
  # ==== Args
  # value: 検査する値
  # allow_reporting_term "missing: control sample"のような
  # ==== Return
  # true/false
  #
  def self.meaningless_value?(value, allow_reporting_term=false)
    ret = false
    if !(value.nil? || value.strip.empty?)
      if allow_reporting_term == false
        null_accepted = @@null_accepted.dup
      else  # reporting termを許容するなら null定義値から削除する
        null_accepted = @@null_accepted.dup.delete_if{|null_value| null_value.start_with?("missing:")}
      end
      if @@null_not_recommended.select {|refexp| value =~ /^(#{refexp})$/i }.any? # null_not_recommendedの正規表現リストにマッチすればNG
        ret = true
      elsif null_accepted.select {|refexp| value =~ /^(#{refexp})$/i }.any?
        ret = true
      else
        # 入力値からnull値を削除する
        null_value_list = null_accepted +  @@null_not_recommended
        null_value_list.each do |null_value|
          value.gsub!(/#{null_value}/i, "")
        end
        # 値を単語単位に区切り、英数字が2文字以上含まれている単語が一つでもあれば意味のある値とみなす。
        meaningful_word = false
        value.split(" ").each do |word|
          if word.scan(/[0-9a-zA-Z]/).length >= 2
            meaningful_word = true
          end
        end
        # 意味のある単語が一つも含まれなければ、null相当値とみなす
        if meaningful_word == false
          ret = true
        end
      end
    end
    ret
  end

  #
  # テキストが正規表現に沿っているかチェックする
  #
  # ==== Args
  # value: 検査する値
  # regex: 正規表現のテキスト "^.{100,}$"
  # ==== Return
  # true/false
  #
  def self.format_check_with_regexp(value, regex)
    value = value.to_s
    regex = Regexp.new(regex)
    ret = false
    if value =~ regex
      ret = true
    end
    ret
  end
end
