require 'erb'
require 'ostruct'

class CommonUtils

  #
  #
  #
  def self.binding_template_with_hash (template, params)
    vars = OpenStruct.new(params)
    if File.exist?(template)
      template = File.read(template)
    end
    query = ERB.new(template).result(vars.instance_eval { binding })
    return query
  end

  #
  # Returns an error message that has assembled from the specified error object
  #
  def self.error_msg (rule_obj, rule_code, params)
    template = rule_obj["rule" + rule_code]["message"]
    message = CommonUtils::binding_template_with_hash(template, params)
    message
  end

  #
  # Returns an error message that has assembled from the specified error object
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
