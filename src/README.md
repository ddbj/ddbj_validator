# DDBJ Validator API


## Requirements

- Ruby
- [Bundler](http://gembundler.com/) (`gem install bundler`)

```sh
$ ruby -v
ruby 2.2.5p319 (2016-04-26 revision 54774) [x86_64-darwin14]
$ bundle -v
Bundler version 1.13.1
```

## Installation
``` sh
  $ cd ddbj_validator
  $ bundle install (--path vendor/bundle)
```

## Start API server
``` sh
$ bundle exec rackup
[2017-07-17 17:45:10] INFO  WEBrick 1.3.1
[2017-07-17 17:45:10] INFO  ruby 2.2.5 (2016-04-26) [x86_64-darwin14]
[2017-07-17 17:45:10] INFO  WEBrick::HTTPServer#start: pid=1970 port=9292
```
