var express = require('express');
var router = express.Router();
var fs = require('fs');
var libxmljs = require('libxmljs');

/* GET home page. */
router.get('/', function (req, res, next) {
    res.render('index', {});
});

router.post('/j2x', function (req, res) {
    var message = (Object.keys(req.body)[0]);
    var messages = [];
    messages.push(message);
    var message_obj = JSON.parse(messages);
    var errors = message_obj["errors"];
    var original_file = message_obj["xml_filename"];
    var xmlfile = fs.readFileSync('./tmp/' + original_file);

     var xmlDoc = libxmljs.parseXml(xmlfile);

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
     }else{
         res.send(xmlfile)
     }

    /*
     for(var i = 0; i < options.length; i++){
     var k = Object.keys(options[i])[0];
     var val = options[i][k];
     //xmlDoc.find("//Attribute[@attribute_name='" + Object.keys(options[i]) + "']")[0].text(Object.values(options[i]));
     xmlDoc.find("//Attribute[@attribute_name='"+ k + "']")[0].text(val);
     }
    */
     //console.log(xmlDoc.find("//Attribute[@attribute_name='sample_name']")[0].text());
     //xmlDoc.find("//Attribute[@attribute_name='sample_name']")[0].text("test111");

});

module.exports = router;
