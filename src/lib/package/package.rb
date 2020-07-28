require 'rubygems'
require 'json'
require 'erb'
require File.dirname(__FILE__) + "/../validator/common/sparql_base.rb"
require File.dirname(__FILE__) + "/../validator/common/common_utils.rb"

class Package < SPARQLBase

  #
  # Initializer
  #
  # ==== Args
  # endpoint: endpoint url
  #
  def initialize (endpoint)
    super(endpoint)
    @template_dir = File.absolute_path(File.dirname(__FILE__) + "/sparql")
  end

  def package_list (version)
    params = {version: version}
    # TODO 1.2系と1.4系でクエリ分ける
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/package_list_1.4.rq", params)
    query(sparql_query)
  end

  # package_groupとpackageのリストをアプリ表示用に階層型に整形して返す
  def package_and_group_list (version)
    params = {version: version}
    # package listを取得
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/package_list_1.4.rq", params)
    package_list = query(sparql_query)
    package_list.each do |row|
      row[:type] = "package"
    end
    #package_list.delete
    # package group listを取得
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/package_group_list_1.4.rq", params)
    package_group_list = query(sparql_query)
    package_group_list.each do |row|
      row[:type] = "package_group"
    end

    # mergeして階層型に整形
    package_list.concat(package_group_list)
    package_tree = []
    package_list.each_with_index do |package_info, idx|
      package_tree = add_package_tree(package_info, package_list, package_tree)
    end
    package_tree
  end

  # treeの中から再帰的にpackage_groupを探す。ヒットすればそのpackage_groupを返し、なければnilを返す
  def find_package_group(tree, group_info)
    return nil if group_info[:type] != "package_group"
    hit_group = tree.find{|row| row[:package_group_name] == group_info[:package_group_name]}
    if hit_group.nil?
      tree.each do |package| #下の階層から検索
        unless package[:package_list].nil? || package[:package_list] == []
          return find_package_group(package[:package_list], group_info) unless find_package_group(package[:package_list], group_info).nil?
        end
      end
      return nil #下の階層にもなければnil
    else
      hit_group
    end
  end

  def add_package_tree(package_info, package_list, tree)
    # 初回に出てきたpackage_groupにlistを追加
    if find_package_group(tree, package_info).nil? && package_info[:type] == "package_group"
      package_info[:package_list] = []
    end

    # 親groupの記載がない(最上位)
    if package_info[:parent_package_group_uri].nil? || package_info[:parent_package_group_uri] == "" # find_package_group(tree, package_info).nil?
      if find_package_group(tree, package_info).nil?
        tree.push(package_info)
      end
      return tree
    end

    # 親を検索
    parent = package_list.find{|row| row[:type] == "package_group" && row[:package_group_uri] == package_info[:parent_package_group_uri]}
    unless parent.nil?
      if find_package_group(tree, parent).nil? #まだ追加されていなければ
        tree = add_package_tree(parent, package_list, tree) #親を追加
      end
      parent_group = find_package_group(tree, parent)
      parent_group[:package_list].push(package_info) if find_package_group(tree, package_info).nil?  #まだ追加されていなければ
    end
    tree
  end

  def attribute_list (version, package_id)
    params = {version: version, package_id: package_id}
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/attribute_list_1.4.rq", params)
    attr_list = query(sparql_query)
    if version.start_with?("1.4")
      sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/attribute_group_list_1.4.rq", params)
      group_list = query(sparql_query)
      attr_list.each do |row|
        match = group_list.find{|group| group[:attribute_name] == row[:attribute_name]}
        unless match.nil?
          row["require_type"] = "has_either_one_mandatory_attribute"
          row["group_name"] = match[:group_name]
        else
          row["group_name"] = ""
        end
      end
    end
    attr_list
  end

  def package_info (version, package_id)
    params = {version: version, package_id: package_id}
    sparql_query = CommonUtils::binding_template_with_hash("#{@template_dir}/package_info_1.4.rq", params)
    ret = query(sparql_query)
    if ret.size == 1
      ret.first
    else
      nil
    end
  end
end