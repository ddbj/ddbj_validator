var express = require('express');
var router = express.Router();
var fs = require('fs');
var libxmljs = require('libxmljs');

/* GET home page. */
router.get('/', function(req, res, next) {
  res.render('index', {});
});

router.post('/j2x', function(req, res){
  var message = (Object.keys(req.body)[0]);
  message = JSON.parse(message);
  //var errors = message["errors"];

  var original_file = message["xml_filename"];
  var xmlfile = fs.readFileSync('./tmp/' + original_file);
  var xmlDoc = libxmljs.parseXml(xmlfile);


  var options = message["selected_option"];

  for(var i = 0; i < options.length; i++){
    var k = Object.keys(options[i])[0];
    var val = options[i][k];
    //xmlDoc.find("//Attribute[@attribute_name='" + Object.keys(options[i]) + "']")[0].text(Object.values(options[i]));
    xmlDoc.find("//Attribute[@attribute_name='"+ k + "']")[0].text(val);
  }

  //console.log(xmlDoc.find("//Attribute[@attribute_name='sample_name']")[0].text());
  //xmlDoc.find("//Attribute[@attribute_name='sample_name']")[0].text("test111");

  res.send(xmlDoc.toString());
  //res.send(xmlfile)
});

module.exports = router;
