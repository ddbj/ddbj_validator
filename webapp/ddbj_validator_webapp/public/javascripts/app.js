(function(){
    //error_message_response model
    var Message = Backbone.Model.extend({
        urlRoot: "/messages",
        idAttribute: "_id",
        defaults: {
            errors: [],
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
        $.get("./views/ddbj_validation_rules.json")
    ).done(function(file1, file2, file3){renderMessage(file1, file2, file3)});

    function renderMessage(file1,file2, file3){
        var error_tmpl = file1[0];
        var group_tmpl = file2[0];
        var rules = file3[0];

        var list_option = $("#hidemenu input[type=radio]:checked").val();
        $("#hidemenu input[type=radio]").change(function(){
            list_option = this.value;
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
                    console.log(error_message);
                    message.save({
                        errors: error_message["errors"],
                        error_size:error_message["error_size"],
                        method: error_message["method"],
                        original_file: error_message["original_file"]});


                    if(list_option == "option-grouped") {
                        // if option Group Error Message selected
                        var grouped_message = d3.nest().key(function(d){return d.id})
                            .entries(error_message.errors);

                        //add message and attributions each grouped messages
                        $.each(grouped_message,function(i, v){
                            var rule_num = "rule" + v.key;
                            var message = rules[rule_num]["message"];
                            message = message.replace(/\:?\s?\'?<%= \w+ %>\'?/g, '');
                            v["message"] = message;
                            v["location"] = rules[rule_num]["location"];
                            v["level"] = v.values[0]["level"];
                            v["correction"] = rules[rule_num]["correction"];
                        });

                        error_message["errors"] = grouped_message;

                        var edit_item = "";

                        var ErrorView = Backbone.View.extend({
                            initialize: function () {
                                _.bindAll(this, "render");
                                this.render();
                            },
                            template: _.template(group_tmpl),
                            render: function () {
                                this.$el.html(this.template(error_message))
                            },
                            events:{
                                'change .result-group input[type=text]': 'onChange'
                            },
                            onChange: function(e){
                                edit_item = $(".result-group input[type=text]").val();

                            }
                        });

                        var error_view = new ErrorView({el: $("#result")});

                        $("#dl_xml").click(function(){
                            error_message["selected_option"] = [{"rel_to_oxygen":edit_item}, {"oxy_stat_samp": "BB"}];
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
                        })
                    }else{
                        //add message and attributions each grouped messages
                        $.each(error_message.errors,function(i, v){
                            var rule_num = "rule" + v.id;
                            v["location"] = rules[rule_num]["location"];
                            v["correction"] = rules[rule_num]["correction"];
                        });
                        // if sequentilal view is selected
                        var ErrorView = Backbone.View.extend({
                            initialize: function () {
                                _.bindAll(this, "render");
                                this.render();
                            },
                            template: _.template(error_tmpl),
                            render: function () {
                                this.$el.html(this.template(error_message))
                            }
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