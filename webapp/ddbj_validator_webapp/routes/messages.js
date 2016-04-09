var express = require('express');
var router = express.Router();
var Message = require("../models/Message");

/* GET home page. */
router.post('/', function(req, res, next) {
    var message = new Message();
    message.errors = req.body.errors;
    message.error_size = req.body.error_size;
    message.method = req.body.method;
    message.original_file = req.body.original_file;
    message.selected = req.body.selected;
    message.updateTime = req.body.updateTime;
    message.save(function(err){
        if(err){
            return next(err)
        }
        res.json(message);
    })
});

router.put('/:id', function(req,res,next){
    Message.findById(req.params.id, function(err, data){
        if(err){
            return next(err)
        }
        data.selected = req.body.selected;
        data.save(function(err){
            if(err){
                return  next(err);
            }
            res.json(data);
        })
    })
})

module.exports = router;
