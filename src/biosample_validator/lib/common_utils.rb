require 'erb'
require 'erubis'

class CommonUtils

  #
  # Returns text that had been binded the hash object as params parameter to the template
  #
  # ==== Args
  # template: string or file path
  # param: a hash for binding
  # ==== Return
  # returns binding result as string
  #
  def self.binding_template_with_hash (template, params)
    if File.exist?(template)
      template = File.read(template)
    end
    result = Erubis::Eruby.new(template).result(params)
    return result
  end

  #
  # Returns an error message that has assembled from the specified error object
  #
  # ==== Args
  # rule_obj: object that is described the rule
  # rule_code: rule_no ex."48"
  # params: a hash object for binding the variable to template ex."{attribute_name: attr_name}"
  # ==== Return
  # returns error message as string
  #
  def self.error_msg (rule_obj, rule_code, params)
    template = rule_obj["rule" + rule_code]["message"]
    message = CommonUtils::binding_template_with_hash(template, params)
    message
  end

  #
  # Returns an error object
  #
  # ==== Args
  # id: rule_no ex."48"
  # message: error message for displaying
  # reference: 
  # level: error/warning 
  # annotation: annotation list for correcting the value 
  # ==== Return
  #
  def self.error_obj (id, message, reference, level, annotation)
    hash = {
             id: id,
             message: message,
             message_ja: "",
             reference: "",
             level: level,
             method: "biosample validator",
             annotation: annotation
           }
    hash
  end

end
