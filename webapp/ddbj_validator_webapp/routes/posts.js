/*
 BioSample controller.
 Kick Biosample Validator with BioSample JSON and
 return validation results as JSON format.
 */
var express = require('express');
var router = express.Router();
var exec = require('child_process').exec;
var execFile = require('child_process').execFile;
var spawn = require('child_process').spawn;
var fs = require('fs');
var xml2js = require('xml2js');
var libxml = require('libxmljs');
var conf = require('config');
var jschardet = require('jschardet');
var formattype = require('format-type');
var json_path = "";
var sample_path = "";
var file_name = "";
var original_name = "";
var format_type = "";

router.post('/upload-tmp', function(req, res){
    item = new Object();
    item["errors"] = [];
    item["exception"] =  "test";
    item["original_file"] = req.file["originalname"];
    item["method"] = "biosample validator";
    item["xml_filename"] = file_name;
    res.send(item)
});

router.post('/upload', function(req, res, next){
    fs.writeFile("./tmp/ok_post.txt", "route.post /upload");
    original_name = req.file['originalname'];
    json_path = conf.read_file_dir + original_name.split(".")[0] + ".json";
    sample_path = conf.read_file_dir + original_name;
    file_name = req.file['filename'];
    var xml2js_parser = new xml2js.Parser({attrkey: "@", charkey: "text"});
    var parseString = require('xml2js').parseString;
    var json_array = [];

    fs.readFile(conf.read_file_dir + file_name, "utf8", function(err, data){
        var type = formattype(data)["type"];
        switch (type){
            case "xml":
                break;
            case "tsv":
                //tsv2json
                exec('ruby ./validator/annotated_sequence_validator/submission_tsv2json '  + conf.read_file_dir + file_name + '> ' + json_path, function(error, stdout, stderr){
                    if(stdout){

                    }
                    if(stderr){
                        fs.writeFile("./tmp/stderr.txt", stderr);
                    }
                    if(error){
                        fs.writeFile("./tmp/err.txt", error);
                    }
                });
                break;
            case "json":
                type = "invalid_value";
                break;
            default:
                type = "invalid_value";
                break;
        }
        go_next(type);
    });

    function go_next(type){
        format_type = type;
        next();
    }

}, function(req, res, next){
    var type = format_type;
    switch(type){
        case "xml":
            var original_name = req.file['originalname'];
            sample_file_path = conf.tmp_file_dir + file_name;
            output_path = conf.tmp_file_dir + original_name.replace("xml", "json");
            exec('ruby ./validator/biosample_validator.rb ' +  sample_file_path + " xml " + output_path + " " + conf.validator_mode, function(error, stdout, stderr){
                //if response is {"undefined: 1!
                // xx.json is invalid json file} call invalid input process
                if(stderr){}
                if(error){
                    render_exception(error);
                }else{
                    // error response ファイル取得
                    var obj = JSON.parse(fs.readFileSync(output_path, 'utf8'));
                    render_result(obj);
                    /*
                    if(obj["status"] == "error"){
                        render_exception(error_list["message"])
                    }else if(obj["status"] == "fail" ) {
                        render_result(obj["failed_list"]);
                    }else if(obj["status"] == "success") {
                        render_result([])
                    }else if(obj["status"] == "error"){
                        render_exception(obj["message"])
                    }else{
                        render_exception("Uncatch exception occured")
                    }
                    */
                    //var error_list = eval(stdout);
                    //render_result(error_list);
                }

            });
            break;
        case "tsv":
            exec('/home/vagrant/ddbj_validator/webapp/ddbj_validator_webapp/validator/annotated_sequence_validator/ddbj_annotated_sequence_validator.pl', {maxBuffer: 1024 * 5000}, function(error, stdout, stderr){
                //exec('/home/vagrant/ddbj_validator/webapp/ddbj_validator_webapp/validator/annotated_sequence_validator/ddbj_annotated_sequence_validator.pl > /home/vagrant/ddbj_validator/webapp/ddbj_validator_webapp/tmp/a_s_output', function(error, stdout, stderr){
                var a_s_output = "";
                if(stdout){
                    a_s_output = stdout;
                }
                if(error){
                    a_s_output = a_s_output + "exception occured: " + error
                }
                render_output(a_s_output);
            });

            break;

        case "invalid_value":
            var item = {};
            var original_name = req.file["originalname"];
            item['errors'] = [];
            item['error_size'] = 0;
            item['exception'] =  "file format is not acceptable. please check your file.";
            item['original_file'] = original_name;
            item['method'] = "biosample validator";
            item['xml_filename'] = file_name;
            res.json(item);
            removeTmpFiles();
            break;
    }

    function render_exception(message){
        //res.render('validator_error', {message:"Exception occured",error: stderr });
        var item = new Object();
        //console.log(message);
        item["errors"] = [];
        item["exception"] =  message;
        item["original_file"] = original_name;
        item["method"] = "biosample validator";
        item["xml_filename"] = file_name;
        res.json(item);
        removeTmpFiles();
    }

    // add some infos to validation message and return response
    function render_result(errors){
        //var errors = JSON.parse(fs.readFileSync(conf.read_file_dir + "test_failed_list.json", 'utf8'));
        var validator_res = new Object();
        errors["failed_list"] ? error_size = errors["failed_list"].length : error_size = 0;
        errors["message"] ? error_message = errors["message"] : error_message = "";
        validator_res["status"] = errors["status"];
        validator_res["format"] = errors["format"];
        validator_res["errors"] = errors["failed_list"];
        validator_res["error_size"] = error_size;
        validator_res["exception"] = error_message;
        validator_res["method"] = "biosample validator";
        validator_res["original_file"] = original_name;
        validator_res["xml_filename"] = file_name;
        res.json(validator_res);
        removeTmpFiles();
    }

    function render_output(output_list){
        fs.writeFile("./tmp/render_output.txt", output_list);
        console.log(output_ilst);
        //fs.writeFile("./tmp/test_a_s", output_list);
        original_name = req.file["originalname"];
        var validator_res = new Object();
        validator_res["status"] = "";
        validator_res["messages"] = output_list;
        validator_res["error_size"] = 0;
        validator_res["exception"] = output_list;
        validator_res["method"] = "annotated sequence validator";
        validator_res["original_file"] = original_name;
        validator_res["xml_filename"] = file_name;
        res.json(validator_res);
        removeTmpFiles();
    }

    function removeTmpFiles(){
        //delete temporary file
        //exec('rm -f ' + json_path, function(error, stdout, stderr){});

        //delete old xml files
        //exec('find ./tmp/ -mtime +1 -exec rm -f {} \;', function(error, stdout, stderr){});
        //exec('find ./tmp/ -mtime +1', function(error, stdout, stderr){console.log(stdout)})
    }
});

module.exports = router;
