/*
BioSample controller.
Kick Biosample Validator with BioSample JSON and
return validation results as JSON format.
 */
var express = require('express');
var router = express.Router();
var exec = require('child_process').exec;
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

//var filewriter = require("filewriter");

router.post('/upload', function(req, res, next){
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
                xml2js_parser.parseString(data, function (err, result) {
                    json_array.push(result);
                    var root_key = Object.keys(json_array[0])[0];
                    if (root_key == "BioSample"){
                        biosample_obj = new Object();
                        json_arrays = [];
                        biosample_obj["BiosampleSet"] = {"BioSample": [json_array[0]["BioSample"]]};
                        json_arrays.push(biosample_obj);
                        json_string = JSON.stringify(json_arrays);
                        fs.writeFile(json_path, json_string);
                    }else if (root_key == "BioSampleSet"){
                        json_string = JSON.stringify(json_array);
                        fs.writeFile(json_path, json_string);
                    }else{
                        type = "invalid_value"
                    }
                });
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
            json_path = conf.read_file_dir + original_name.split(".")[0] + ".json";
            exec('ruby ./validator/biosample_validator.rb ' +  json_path, function(error, stdout, stderr){
                if(stdout){
                    var error_list = eval(stdout);
                    render_result(error_list);
                }
                if(stderr){
                    console.log('stderr: ' + stderr);
                    render_exception(stderr);
                }
                if(error !== null){
                    console.log('Exec error: ' + error);
                }
            });
            break;
        case "tsv":
            exec('perl ./validator/annotated_sequence_validator/ddbj_annotated_sequence_validator.pl ' + json_path, function(error, stdout, stderr){
                if(stdout){
                    res.json(stdout)
                    fs.writeFile("./tmp/stdout_perl.json", stdout);
                }
                if(stderr){
                    fs.writeFile("./tmp/stderr_perl.txt", stderr);
                }
                if(error){
                    fs.writeFile("./tmp/err_perl.txt", error);
                }
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

    function render_exception(stderr){
        //res.render('validator_error', {message:"Exception occured",error: stderr });
        var item = new Object();
        item['errors'] = [];
        item['error_size'] = item['errors'].length;
        item['exception'] =  "Exception occured, " + stderr;
        item['original_file'] = original_name;
        item['method'] = "biosample validator";
        item['xml_filename'] = file_name;
        res.json(item);
        removeTmpFiles();
    }

    // add some infos to validation message and return response
    function render_result(error_list){
        //var biosample_json = JSON.parse(fs.readFileSync(json_path, 'utf8'));
        var item = new Object();
        item['errors'] = error_list;
        item['error_size'] = item['errors'].length;
        item['exception'] = "";
        item['method'] = "biosample validator";
        item['original_file'] = original_name;
        item['xml_filename'] = file_name;
        res.json(item);
        removeTmpFiles();
    }
    function removeTmpFiles(){
        //delete temporary json file
        exec('rm -f ' + json_path, function(error, stdout, stderr){});

        //delete old xml files
        exec('find ./tmp/ -mtime +1 -exec rm -f {} \;', function(error, stdout, stderr){});

    }
});

module.exports = router;
