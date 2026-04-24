require 'erb'

# 各 validator のチェック結果を error hash / suggested-annotation hash に組み立てる純関数群。
#
# error hash のフォーマットは Wiki を参照:
# https://github.com/ddbj/ddbj_validator/wiki/Validator-API
module ErrorBuilder
  AUTO_ANNOTATION_MSG = "An automatically-generated correction will be applied."

  #
  # ルール定義から error hash を組み立てて返す。
  #
  # ==== Args
  # rule: rule の Hash
  # file_path: 検証対象のファイルパス (error hash の source フィールド)
  # annotation: annotation の配列
  # auto_annotation: auto annotation 由来のエラーなら true (末尾に AUTO_ANNOTATION_MSG を追記)
  #
  def self.error_obj (rule, file_path, annotation, auto_annotation = false)
    message = rule["message"]
    message = "#{message} #{AUTO_ANNOTATION_MSG}" if auto_annotation
    {
      id:         rule["code"],
      message:    message,
      reference:  rule["reference"],
      level:      rule["level"],
      external:   rule["internal_ignore"],
      method:     rule["rule_class"],
      object:     rule["object"],
      source:     file_path,
      annotation: annotation
    }
  end

  #
  # rule definition の message テンプレートに params を埋め込んでエラーメッセージ文字列を返す。
  #
  # ==== Args
  # rule_obj:  rule 定義のトップレベル Hash
  # rule_code: "BS_R0048" のような rule code (内部で "rule" prefix 付きで引く)
  # params:    テンプレートへ埋め込む変数の Hash
  #
  def self.error_msg (rule_obj, rule_code, params)
    ERB.new(rule_obj["rule#{rule_code}"]["message"]).result_with_hash(params || {})
  end

  #
  # Suggest 形式の annotation hash を返す。デフォルト key 名 ("Suggested value") 以外にしたい
  # ケース (複数の Suggested 項目を識別したい等) のために key 名も受け取る版。
  #
  # ==== Args
  # key:                  "Suggested value" 以外にしたい場合の項目名
  # suggested_values:     候補値の配列
  # target_key:           適用先の列名 (例 "Attribute value")
  # location:             ファイル内の位置情報 (配列)
  # is_auto_annotation:   auto annotation なら true、そうでなければ suggestion 扱い
  #
  def self.suggested_annotation_with_key (key, suggested_values, target_key, location, is_auto_annotation)
    key = "Suggested value" if key.nil? || key == ""
    hash = {
      key:             key,
      suggested_value: suggested_values,
      target_key:      target_key,
      location:        location
    }
    if is_auto_annotation
      hash[:is_auto_annotation] = true
    else
      hash[:is_suggestion] = true
    end
    hash
  end

  #
  # Suggest 形式の annotation hash を返す (デフォルト key 名 "Suggested value" 版)。
  #
  def self.suggested_annotation (suggested_values, target_key, location, is_auto_annotation)
    suggested_annotation_with_key("Suggested value", suggested_values, target_key, location, is_auto_annotation)
  end

  #
  # error hash に含まれる auto-annotation の提案値を 1 件返す。無ければ nil。
  #
  def self.auto_annotation (error_obj)
    return nil if error_obj.nil? || error_obj[:annotation].nil?
    anno = error_obj[:annotation].find { it[:is_auto_annotation] == true }
    anno && anno[:suggested_value].first
  end

  #
  # error hash 中で target_key が一致する auto-annotation の提案値を 1 件返す。無ければ nil。
  #
  def self.auto_annotation_with_target_key (error_obj, target_key_value)
    return nil if error_obj.nil? || error_obj[:annotation].nil?
    anno = error_obj[:annotation].find { it[:is_auto_annotation] == true && it[:target_key] == target_key_value }
    anno && anno[:suggested_value].first
  end
end
