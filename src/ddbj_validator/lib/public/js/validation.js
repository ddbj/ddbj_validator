(function(){
    //error_message_response model
    /*
    var Message = Backbone.Model.extend({
        urlRoot: "/messages",
        idAttribute: "_id",
        defaults: {
            errs: "",
            error_size: 0,
            method: "",
            original_file: "",
            selected: [],
            updateTime: new Date()
        }
    });
    */
    var api_version = "0.9.0";

    var output_f = "";
    $('#select_file').click(function(){
        $('input[id=biosample]').click();
    });
    $('#biosample').change(function () {
        if ($('#biosample')[0].files.length > 0) {
            output_f = $('#biosample')[0].files[0].name;
            $('#file_name').val(output_f);
        }
    });

    $.when(
        $.get("./ejs/error_message.ejs"),
        $.get("./ejs/error_message_group.ejs"),
        $.get("./ejs/annotated_sequence.ejs"),
        $.get("./ejs/data_info.ejs"),
        $.get("./ejs/success.ejs")
    ).done(function(tmpl_bs, tmpl_bs_group, tmpl_as, tmpl_info, tmpl_ok){renderMessage(tmpl_bs, tmpl_bs_group, tmpl_as, tmpl_info, tmpl_ok)});

    function renderMessage(tmpl_bs,tmpl_bs_group, tmpl_as, tmpl_info, tmpl_ok){

        var error_tmpl = tmpl_bs[0];
        var group_tmpl = tmpl_bs_group[0];
        var anottated_sequence_tmpl = tmpl_as[0];
        var info_tmpl = tmpl_info[0];
        var success_tmpl = tmpl_ok[0];

        var list_option = $("input[name=list-option]:checked").val();
        $("input[name=list-option]").change(function(){
            list_option = this.value;
        });

        var current_target = "file";
        $("#select_source li").click(function(e){
           current_target =e.target["dataset"]["source"];
        });

        $("#check_data").click(function () {
            if (output_f == "") {
                alert("Please select a file");
            } else {
                $("#result").empty();
                showLoading();
                var form = $("#submit_data").get()[0];
                var formData = new FormData(form);
                var ajax_obj = {};

                ajax_obj = {
                    url: "./api/" + api_version + "/validation",
                    method: "post",
                    dataType: "json",
                    data: formData,
                    processData: false,
                    contentType: false
                };

                $.ajax(ajax_obj).done(function (response) {
                    /*
                    var message = new Message();
                    message.save({
                        errors: error_message["errors"],
                        error_size:error_message["error_size"],
                        method: error_message["method"],
                        original_file: error_message["original_file"]});
                        */

                    var result = JSON.parse(response);
                    //TODO add this info to api response?
                    result["original_file"] = $('#file_name').val();
                    result["method"] = "biosample validator"; 
                    var tmpl = "";
                    if (result["status"] == "fail" ) {
                      result["error_size"] = result.failed_list.length;
                      if(list_option == "option-grouped") {
                        // create nested data
                        var grouped_message = d3.nest().key(function (d) {
                                return d.id
                            })
                            .entries(result.failed_list);
                        //add message and attributions each grouped messages
                        $.each(grouped_message, function (i, v) {
                            v["message"] = v.values[0]["message"];
                            v["level"] = v.values[0]["level"];
                        });
                        // "errors" is object grouped by validation rule type
                        result["errors"] = grouped_message;
                        tmpl = group_tmpl;
                      } else if (list_option == "option-sequential") {
                          result["errors"] = result.failed_list;
                          tmpl = error_tmpl;
                      }
                    } else if (result["status"] == "success" ) {
                       result["error_size"] = 0;
                       tmpl = success_tmpl;
                    } else if (result["status"] == "error" ) {
                       tmpl = info_tmpl;
                    } else {
                       tmpl = info_tmpl;
                    }
                    var ErrorView = Backbone.View.extend({
                        initialize: function () {
                            _.bindAll(this, "render");
                            this.render();
                        },
                        template: _.template(tmpl),
                        render: function () {
                            this.$el.html(this.template(result))
                        }
                    });
                    var error_view = new ErrorView({el: $("#result")});
                }).always(function () {
                    //
                });
            }
        });

        //download
        $("#dl_xml").click(function(){
            var auto_annotation_vals = [];
            $("td[data-auto-annotation='true']").each(function(){
                var obj = {}
                obj["val"] = $(this).text();
                obj["location"] = $(this).data("location");
                auto_annotation_vals.push(obj);
            });
            //auto_annotation_vals.push($("td[data-auto-annotation='true']").text().replace(/^\s+|\s+$/g));
            //console.log($("td[data-auto-annotation='true']").text());
            //error_message["fixed_values"] = fixed_values;
            var auto_annotation_obj = {"annotaions": auto_annotation_vals, "file_name": error_message["xml_filename"], "original_name": error_message["original_file"]};
            //console.log(auto_annotation_obj);
            $.ajax({
                url: "./j2x",
                method: "post",
                dataType: "json",
                data: auto_annotation_obj
            }).done(function(data){
                //success:function(data, status, xhr){
                    var blob = new Blob([data], {"type": "application-xml"});
                    var a = document.createElement("a");
                    var filename = "validated_" + error_message["original_file"];
                    a.href = URL.createObjectURL(blob);
                    a.target = "_blank";
                    a.download = filename;
                    a.click();

            }).fail(function(data){
                var blob = new Blob([data["responseText"]], {"type": "application-xml"});
                var a = document.createElement("a");
                var filename = "validated_" + error_message["original_file"];
                a.href = URL.createObjectURL(blob);
                a.target = "_blank";
                a.download = filename;
                a.click();
            });
        })

        function showLoading() {
            $("#result").append("<div id='loading'><div class='loader'></div></div>");
        }
        /*
         function removeLoader(){$("#loading").remove();}
        */
    }

}());
