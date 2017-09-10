(function(){
    var api_url = "/api";

    //ファイル選択ボタン押下時に選択ウィンドウを表示
    var output_f = "";
    $('.btn.file_select').click(function(){
        var clicked = $(this).attr("id");
        if (clicked === 'biosample_file_select') {
            $('input[id=biosample]').click();
        } else if (clicked === 'bioproject_file_select') {
            $('input[id=bioproject]').click();
        }
    });

    //ファイル選択ウィンドウにてファイルが選択された場合、ファイル名をテキストボックスに表示
    $('.selected_file').change(function () {
        if ($(this)[0].files.length > 0) {
            output_f = $(this)[0].files[0].name;
            var changed = $(this).attr("id");
            if (changed === 'biosample') {
                $('#biosample_file_name').val(output_f);
            } else if (changed === 'bioproject') {
                $('#bioproject_file_name').val(output_f);
            }
        }
    });

    //表示オプションの設定と切り替え
    var list_option = $("input[name=list-option]:checked").val();
    $("input[name=list-option]").change(function(){
        list_option = this.value;
    });

    //テンプレートファイルをロードする
    $.when(
        $.get("/ejs/error_message.ejs"),
        $.get("/ejs/error_message_group.ejs"),
        $.get("/ejs/result_summary.ejs")
    ).done(function(tmpl_bs, tmpl_bs_group, tmpl_summary){ready(tmpl_bs, tmpl_bs_group, tmpl_summary)});

    //初期状態
    function ready(tmpl_bs,tmpl_bs_group, tmpl_summary){

        var error_tmpl = tmpl_bs[0];
        var group_tmpl = tmpl_bs_group[0];
        var summary_tmpl = tmpl_summary[0];

        //validationボタン押下時
        $("#check_data").click(function () {
            //ユーザが選択したファイル名をformから取得
            var file_list = {};
            $('.selected_file').each(function() {
                if ($(this)[0].files.length > 0) {
                    file_list[$(this).attr("id")] = $(this)[0].files[0].name;
                }
            });
            if (Object.keys(file_list).length == 0) { //ファイルが一つも選択されていない場合はエラー
                alert("Please select a file");
            } else {
                $("#result").empty(); //clear
                showLoading(); //クルクル表示
                $.ajax({
                    //validationAPIにファイル(formData)を送信
                    url: api_url + "/validation",
                    method: "post",
                    data: new FormData($("#submit_data").get()[0]),
                    processData: false,
                    contentType: false
                }).done(function (response) {
                    //成功すると受付UUIDが返されるので、validation処理完了までポーリングする
                    polling(response.uuid);
                }).fail(function (data) {
                    $("#result").empty(); //clear
                    if (Math.floor(data.status / 100) == 4) {
                        render_user_error(data);
                    } else {
                        render_system_error();
                    }
                });
            }
        });

        //validationのstatusをAPIにポーリングを続けるメソッド
        //finishedに変わったらvalidationの結果を取得するAPIを叩く
        function polling(uuid) {
            $.ajax({
                url: api_url + "/validation/" + uuid + "/status"
            }).done(function(data) {
                if (data.status === "accepted" || data.status === "running") { //まだ実行中なので一定時間待って再びstatusを問い合わせる
                    setTimeout(function() {polling(uuid)},2000);
                } else { //validation終了したので結果をAPIに問い合わせる
                    $.ajax({
                        url: api_url + "/validation/" + uuid
                    }).done(function(data) {
                        render(data);
                    }).fail(function(data) {
                        if (Math.floor(data.status / 100) == 4) {
                            render_user_error(data);
                        } else {
                            render_system_error();
                        }
                    });
                }
            }).fail(function(data) {
                if (Math.floor(data.status / 100) == 4) {
                    render_user_error(data);
                } else {
                    render_system_error();
                }
            });
        }
        //ユーザが選択したファイル名をformから取得する
        function selected_file_list() {
            var file_list = {};
            $('.selected_file').each(function() {
                if ($(this)[0].files.length > 0) {
                    file_list[$(this).attr("id")] = $(this)[0].files[0].name;
                }
            });
            return file_list;
        }
        //validationの結果を画面表示する
        function render(response) {
            var result = {};
            result = response["result"];//validationの結果を代入
            result["file_list"] = selected_file_list();
            result["error_count"] = result["stats"]["error_count"];
            result["warning_count"] = result["stats"]["warning_count"];
            var tmpl = ""; //表示用テンプレート
            var message_count = result["error_count"] + result["warning_count"];
            if (message_count > 0) { //validationでerror/wawrningがある場合
                if (result["error_count"] == 0) { //warningのみの場合
                    result["title_message"] = "This document was successfully checked as DDBJ XML";
                    result["result_message"] = "Passed, " + result["warning_count"] + " warning(s)";
                    result["status"] = "warning";
                } else { // validationでerrorがある場合
                    result["title_message"] = "Errors found while checking this document as DDBJ XML";
                    result["result_message"] = result["error_count"] + " errors(s)"
                    result["status"] = "unpassed";
                    if (result["warning_count"] > 0) {
                        result["result_message"] += ", " + result["warning_count"] + " warning(s)";
                    }
                }
                result["all_error_size"] = result.messages.length;
                if(list_option == "option-grouped") { //グルーピング表示が選択されている場合
                    // create nested data
                    var grouped_message = d3.nest().key(function (d) {
                        return d.method + "_" + d.id
                    }).entries(result.messages);
                    //add message and attributions each grouped messages
                    $.each(grouped_message, function (i, v) {
                        v["message"] = v.values[0]["message"];
                        v["level"] = v.values[0]["level"];
                    });
                    // "errors" is object grouped by validation rule type
                    result["errors"] = grouped_message;
                    tmpl = group_tmpl; //表示テンプレートを指定
                } else if (list_option == "option-sequential") { //シーケンシャル表示が選択されている場合
                    result["errors"] = result.messages;
                    tmpl = error_tmpl;  //表示テンプレートを指定
                }
            } else { //validationが全て通った場合
                result["title_message"] = "This document was successfully checked as DDBJ XML";
                result["result_message"] = "Passed";
                result["status"] = "passed";
                tmpl = summary_tmpl; //表示テンプレートを指定
            }
            //指定された表示テンプレートを使用して描画
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
        }

        //ユーザのパラメータが不正だった場合にメッセージを画面表示する
        function render_user_error(response) {
            var result = {};
            result["file_list"] = selected_file_list();
            result["title_message"] = "An error occurred during the validation process!";
            result["result_message"] = JSON.parse(response.responseText).message;
            result["status"] = "error";
            tmpl = summary_tmpl; //表示テンプレートを指定
            //指定された表示テンプレートを使用して描画
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
        }

        //システムエラーが発生した場合にメッセージを画面表示する
        function render_system_error() {
            var result = {};
            result["file_list"] = selected_file_list();
            result["title_message"] = "An error occurred during the validation process!";
            result["result_message"] = "An error occurred during the validation process. Please try again later";
            result["status"] = "error";
            tmpl = summary_tmpl; //表示テンプレートを指定
            //指定された表示テンプレートを使用して描画
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
        }

        // 問い合わせ中を示すアニメーション描画
        function showLoading() {
            $("#result").append("<div id='loading'><div class='loader'></div></div>");
        }
    }
}());
