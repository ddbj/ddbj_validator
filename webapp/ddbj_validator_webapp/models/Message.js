var mongoose = require('mongoose');
var Schema = mongoose.Schema;

var MessageSchema = new Schema({
    name: String,
    age: String
});

module.exports = mongoose.model("Message", MessageSchema);