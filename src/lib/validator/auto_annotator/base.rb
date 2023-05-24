require 'yaml'
require 'json'

class AutoAnnotatorBase

  def initialize
  end

  #
  # Validation結果のjsonファイルから
  # Auto-annotationの情報が記述されたエラーだけを抽出してリストで返す
  #
  # ==== Args
  # validate_result_file: validation結果ファイル(json)のバス
  # filetype: ファイルの種類 e.g. biosample, bioproject...
  # ==== Return
  # Auto-annotationの情報が記述されたエラーのリスト
  # ex.
  # [
  #  {"key"=>"Suggested value",
  #   "suggested_value"=>["missing"],
  #   "target_key"=>"Attribute value",
  #   "location"=>["//BioSample[1]/Description/Organism/OrganismName"],
  #   "is_auto_annotation"=>true
  #  },
  #  ...
  # ]
  #
  def get_annotated_list (validate_result_file, filetype)
    auto_annotation_list = []
    result_json = JSON.parse(File.read(validate_result_file))
    unless result_json["messages"].nil?
      error_list = result_json["messages"].select {|error| error["method"].downcase == filetype.downcase }
      error_list.each do |error|
        an = error["annotation"].select do |annotation|
          !annotation["is_auto_annotation"].nil? && annotation["is_auto_annotation"] == true
        end
        auto_annotation_list.concat(an)
      end
    end
    auto_annotation_list
  end
end