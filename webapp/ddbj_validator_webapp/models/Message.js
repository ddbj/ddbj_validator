var mongoose = require('mongoose');
var Schema = mongoose.Schema;

var MessageSchema = new Schema({
    erros: Array,
    error_size: Number,
    method: String,
    original_file: String,
    selected: Array,
    updateTime: Date
});

module.exports = mongoose.model("Message", MessageSchema);