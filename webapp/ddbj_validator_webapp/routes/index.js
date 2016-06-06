var express = require('express');
var router = express.Router();
var fs = require('fs');
var libxmljs = require('libxmljs');
//var exec = require('child_process').exec;
//var execFile = require('child_process').execFile;
//var spawn = require('child_process').spawn;
var xml2js = require('xml2js');
var conf = require('config');
var jschardet = require('jschardet');

/* GET home page. */
router.get('/', function (req, res, next) {
    res.render('index', {});
});

router.post('/j2x', function (req, res) {
    //console.log(req.body);
    //JSON.parse(req.body);
    var annotations  = new Object();
    var annotation_req = req.body;
    var file_name = "";
    var original_name = "";
    for(var k in annotation_req){
        if(req.body.hasOwnProperty(k)) {
            if (k == "file_name") {
                file_name = annotation_req[k];
            } else if(k == "original_name"){
                original_name = annotation_req[k];
            }
        else{
                var i = k.split(/\W/)[1];
                var kp = k.split(/\W/)[3];
                var kw = "annotation_" + i;
                if (!annotations[kw]) {
                    annotations[kw] = {}
                };
                switch (kp) {
                    case "val":
                        annotations[kw]["val"] = annotation_req[k];
                        break;
                    case "location":
                        annotations[kw]["location"] = annotation_req[k];
                        break;
                }
            }
        }
    }
    //console.log(annotations);
    //console.log(original_name + " : " + file_name);

    //var message = (Object.keys(req.body)[0]);
    //var length = Object.keys(annotations).length;
    //var messages = [];
    //messages.push(message);
    //console.log(messages);
    //var message_obj = JSON.parse(messages);
    //var errors = message_obj["errors"];
    //var original_file = message_obj["xml_filename"];
    var xmlfile = fs.readFileSync('./tmp/' + file_name);
    var xmlDoc = libxmljs.parseXml(xmlfile);
    /*
     if(sample_ids = message_obj["fixed_values"]){
         for (var sample_id in sample_ids) {
             var fixed_values = sample_ids[sample_id];
             for(var fixed_value in fixed_values) {
                 var val = fixed_values[fixed_value]["input_value"];
                 var loc = fixed_values[fixed_value]["location"];
                 var loc = loc.replace(/\W/gi, "");

                 obj = {
                     attribute : function(){
                         xmlDoc.find("//Attribute[@attribute_name='" + fixed_value + "']")[0].text(val);
                     },
                     bioproject_id :function(){
                         xmlDoc.find("//Attribute[@attribute_name='" + fixed_value + "']")[0].text(val);
                     }
                 };
                 callReplacement = function(location){
                     obj[location]();
                 };
                 callReplacement(loc);

                 //xmlDoc.find("//Attribute[@attribute_name='" + fixed_value + "']")[0].text(val);
             }
         }
         res.send(xmlDoc.toString());
     }
     */
     if(Object.keys(annotations).length > 0){
         for(var i = 0; i < Object.keys(annotations).length; i++){
             var obj_key = Object.keys(annotations)[i];
             var location = annotations[obj_key]["location"];
             var val = annotations[obj_key]["val"];
             xmlDoc.find(location)[0].text(val);
         }
         //res.send(xmlfile);
         res.send(xmlDoc.toString());
     }
     else{
         res.send(xmlfile)
     }

});

module.exports = router;
