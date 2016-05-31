(function(){
    //error_message_response model
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

    var output_f = "";
    $('#select_file').click(function(){
        $('input[id=xml_input]').click();
    });
    $('#xml_input').change(function () {
        output_f = $('#xml_input')[0].files[0].name;
        $('#file_name').val(output_f);
    });

    $.when(
        $.get("./views/error_message.ejs"),
        $.get("./views/error_message_group.ejs"),
        $.get("./views/annotated_sequence.ejs"),
        $.get("./views/data_info.ejs")
        //$.get("./views/ddbj_validation_rules.json")
    ).done(function(tmpl_bs, tmpl_bs_group, tmpl_as, tmpl_info){renderMessage(tmpl_bs, tmpl_bs_group, tmpl_as, tmpl_info)});

    function renderMessage(tmpl_bs,tmpl_bs_group, tmpl_as, tmpl_info){
        var error_tmpl = tmpl_bs[0];
        var group_tmpl = tmpl_bs_group[0];
        var anottated_sequence_tmpl = tmpl_as[0];
        var info_tmpl = tmpl_info[0];
        //下記不要
        //var rules = rule_list[0];

        var list_option = $("#hidemenu input[type=radio]:checked").val();
        $("#hidemenu input[type=radio]").change(function(){
            list_option = this.value;
        });

        $("#check_data_tmp").click(function () {
            $.ajax({
                url: "./upload",
                method:"post",
                dataType: "json"
            }).done(function(res){
                console.log(res);
            })
        });

        $("#check_data").click(function () {
            if (output_f != "") {
                showLoading("test_loading");
                var form = $("#submit_data").get()[0];
                var formData = new FormData(form);

                $.ajax({
                    url: "./upload",
                    method: "post",
                    dataType: "json",
                    data: formData,
                    processData: false,
                    contentType: false
                }).done(function (error_message) {
                    //error_message_response object
                    var message = new Message();
                    message.save({
                        errors: error_message["errors"],
                        error_size:error_message["error_size"],
                        method: error_message["method"],
                        original_file: error_message["original_file"]});

                    if(error_message["method"] == "annotated sequence validator"){

                        var ErrorView = Backbone.View.extend({
                            initialize: function () {
                                _.bindAll(this, "render");
                                this.render();
                            },
                            template: _.template(anottated_sequence_tmpl),
                            render: function(){
                                this.$el.html(this.template(error_message))
                            }
                        });
                        var error_view = new ErrorView({el: $("#result")});
                    // biosample case
                    }else if(list_option == "option-grouped") {
                        // create nested data
                        console.log(error_message);
                        if(error_message["status"] == "fail") {
                            var grouped_message = d3.nest().key(function (d) {
                                    return d.id
                                })
                                .entries(error_message.errors);
                            //add message and attributions each grouped messages
                            $.each(grouped_message, function (i, v) {
                                v["message"] = v.values[0]["message"];
                                v["level"] = v.values[0]["level"];
                            });
                            error_message["errors"] = grouped_message;
                        }
                        switch (error_message["status"]){
                            case "fail":
                                console.log("f0");
                                tmpl = group_tmpl;
                                break;
                            default:
                                console.log("f1");
                                tmpl = info_tmpl;
                                break;
                        }

                        // initialize fixed data object
                        var fixed_items =[];
                        var fixed_values = {};
                        var fixed_value = {};
                        var ErrorView = Backbone.View.extend({
                            initialize: function () {
                                _.bindAll(this, "render");
                                this.render();
                            },
                            template: _.template(tmpl),
                            render: function () {
                                this.$el.html(this.template(error_message))
                            }/*,
                            events:{
                                'change .result-group input[type=text]': 'onChange'
                            },
                            onChange: function(e){
                                var input_name = e.target["name"];
                                var input_value = e.target["value"];
                                var input_location = e.target["dataset"]["location"];
                                var biosample_id = e.target["dataset"]["sample"];

                                //
                                if (fixed_values[biosample_id]){
                                    fixed_values[biosample_id][input_name] = {"input_value":input_value,"location": input_location };
                                }else{
                                    var fixed_value = {};
                                    fixed_value[input_name] = {"input_value":input_value,"location": input_location };
                                    fixed_values[biosample_id] = fixed_value;
                                }
                            }*/
                        });

                        var error_view = new ErrorView({el: $("#result")});

                        $("#dl_xml").click(function(){
                            console.log($("td[data-auto-annotation='true']").text());

                            /*
                            //error_message["fixed_values"] = fixed_values;
                            $.ajax({
                                url: "./j2x",
                                method: "post",
                                data: JSON.stringify(error_message),
                                success:function(data){
                                    var blob = new Blob([data], {"type": "application-xml"});
                                    var a = document.createElement("a");
                                    var filename = "validated_" + error_message["original_file"];
                                    a.href = URL.createObjectURL(blob);
                                    a.target = "_blank";
                                    a.download = filename;
                                    a.click();
                                }
                            });
                            */

                        })
                    }else{
                        // biosample error response: sequential view
                        $.each(error_message.errors,function(i, v){
                            //var rule_num = "rule" + v.id;
                            //v["location"] = rules[rule_num]["location"];
                            //v["correction"] = rules[rule_num]["correction"];
                        });
                        console.log(error_message);
                        switch (error_message["status"]){
                            case "fail":
                                tmpl = error_tmpl;
                                break;
                            default:
                                tmpl = info_tmpl;
                                break;
                        }
                        var ErrorView = Backbone.View.extend({
                            initialize: function () {
                                _.bindAll(this, "render");
                                this.render();
                            },
                            template: _.template(tmpl),
                            render: function () {
                                this.$el.html(this.template(error_message))
                            }/*,
                            events:{
                                'change .result-group input[type=text]': 'onChange'
                            },
                            onChange: function(e){
                                var input_name = e.target["name"];
                                var input_value = e.target["value"];
                                var input_location = e.target["dataset"]["location"];
                                var biosample_id = e.target["dataset"]["sample"];

                                //
                                if (fixed_values[biosample_id]){
                                    fixed_values[biosample_id][input_name] = {"input_value":input_value,"location": input_location };
                                }else{
                                    var fixed_value = {};
                                    fixed_value[input_name] = {"input_value":input_value,"location": input_location };
                                    fixed_values[biosample_id] = fixed_value;
                                }
                            }*/
                        });
                        var error_view = new ErrorView({el: $("#result")});
                    }
                }).always(function () {
                    //
                });
            }
        });

        function showLoading() {
            $("#result").append("<div id='loading'><div class='loader'></div></div>");
        }
        /*
         function removeLoader(){$("#loading").remove();}
        */

    }



}());