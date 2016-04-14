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
var conf = require('config');
var jschardet = require('jschardet');
var formattype = require('format-type');
var json_path = "";
var file_name = "";
var original_name = "";
var format_type = "";

//var filewriter = require("filewriter");

router.post('/upload', function(req, res, next){
    original_name = req.file['originalname'];
    json_path = conf.read_file_dir + original_name.split(".")[0] + ".json";
    file_name = req.file['filename'];
    var xml2js_parser = new xml2js.Parser({attrkey: "@", charkey: "text"});
    var parseString = require('xml2js').parseString;
    var json_array = [];

    fs.readFile(conf.read_file_dir + file_name, "utf8", function(err, data){
        var type = formattype(data)["type"];
        switch (type){
            case "xml":
                //check sample and wrap root_node

                //
                xml2js_parser.parseString(data, function (err, result) {
                    json_array.push(result);
                    json_string = JSON.stringify(json_array);
                    fs.writeFile(json_path, json_string);
                });
                break;
            case "tsv":
                console.log("tsv");
                break;
            case "json":
                console.log("json");
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
            break
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
        var biosample_json = JSON.parse(fs.readFileSync(json_path, 'utf8'));
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
        /*
        //delete old xml files
        exec('find ./tmp/ -mtime +1 -exec rm -f {} \;', function(error, stdout, stderr){});
        */
    }
});

module.exports = router;