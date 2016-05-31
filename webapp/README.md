# DDBJ Validation Service

## 仮想環境の取得とサービスの起動

DDBJ Validation Srviceは、Vagratn & Virtual BoxのBoxとして提供されます。

最新のBoxは下記URLより取得してください

[http://vagrant-file-dvs.bmu.jp/package.box](http://vagrant-file-dvs.bmu.jp/package.box)

Vagrant upの後、サービスを開始するために環境内で下記コマンドを実行し手動で必用なサービスを起動してください。

    // Expressの起動
    cd /home/vagrant/ddbj_validator/webapp/ddbj_validator_webapp
    forever start bin/www
    
    // Unicornの起動
    cd /home/vagrant/ddbj_validator/webapp/BioSample_XML_API
    unicorn -c unicorn.rb -D -p 9292
    

## システム仕様

- サーバOS：Ubuntu14.04LTS
- 仮想環境：Vagrant & Virtual box
- アプリケーション言語：Ruby（2.x）, Node.js(v0.10.x)
- データベース：MongoDB
- Webフレームワーク（サーバサイド）：Node.js - Express(v4.x)
- Webフレームワーク（クライアントサイド）：Backbone.js
- アプリケーションサーバ：Express - forever - nginx(リバースプロキシ、予定)


## ディレクトリ・ファイル構成


```

/home/ubuntu/ddbj_validator/webapp
  ├─  app.js                  アプリケーション・エンドポイント
  ├─  package.json            パッケージ管理ファイル
  ├─　bin/
  │   └─  www                 アプリケーション起動スクリプト
  │ 
  ├─　config/                  設定ファイルディレクトリ
  │   └─  default.json      
  │ 
  ├─　models/   
  │   └─  Message.js           errorレスポンスを保存するためのモデル
  │ 
  ├─　node_modules/             npm installした依存ライブラリを配置したディレクトリ         
  │   └─  ...          
  │ 
  ├─　public/                   クライアントサイドで使われるアセット         
  │   ├─  fonts/   
  │   │    └─  glyphicons...    Bootstrapで利用するアイコンフォント
  │   │ 
  │   ├─  images/   
  │   │    └─  gif-load.gif     now loading表示時のアニメーションgif
  │   │ 
  │   ├─  javascripts/          
  │   │    ├─  app.js           サンプルデータのPOSTや表示の非同期処理に関するスクリプト
  │   │    ├─  backbone.js      クライアントサイドのjavascriptフレームワーク
  │   │    ├─  bootstrap.js     レスポンシブな表示に関わるフレームワーク
  │   │    ├─  d3.js            サンプルデータの配列計算に利用
  │   │    ├─  jquery.js        Backbone.jsの依存ライブラリ
  │   │    └─  underscored      Backbone.jsの依存ライブラリ
  │   │
  │   ├─  stylesheets/
  │   │    ├─  style.css
  │   │    └─  validator.css
  │   │ 
  │   └─  views/                非同期なViewの生成に関わるテンプレートとロジックのディレクトリ
  │        ├─  ddbj_validation_rules.json
  │        ├─  error_message.ejs
  │        └─  error_message_group.ejs
  │
  ├─　routes/                   リクエストハンドラ    
  │   ├─  index.js              トップページとxml生成に関わるコントローラ
  │   ├─  messages.js           エラーメッセージログの非同期な更新のためのコントローラ
  │   ├─  post.js               サンプルファイルのPOSTやvalidatorの呼出しに関わるコントローラ
  │   └─  users.js  
  │   
  ├─　tmp/                      一時ファイルを配置するディレクトリ
  │   └─  ... 
  │
  ├─　validator/               validatorのアセットを設置するディレクトリ
  │   ├─  biosample_validator.rb
  │   ├─  organism_package_validator.rb 
  │   ├─  conf/  
  │   ├─  data/
  │   ├─  lib/
  │   └─  sparql/ 
  │
  └─　views/                     サーバサイドでのレンダリングに利用されるテンプレートディレクトリ
     └─   index.ejs             

     
```  


## インストール環境

* アプリケーションはMacOS(10.9)およびUbuntu 14.04.4LTSで動作確認を行っています。
* アプリケーションの起動には以下ライブラリが必用です。
 - node.js
 - ruby
 - libxml2 (apt-get install)
 - libxml2-dev (apt-get install)
 - forever (npm install)
 - libxmljs (npm install)
 - node-gyp (npm install -g)
 

Webアプリケーションは3000番のportを利用します。下記の様なアドレスでローカルで起動したアプリケーションを利用することができます。

    例）
    http://localhost:3000    

配布するコンテナなどでは、nginxによるリバースプロキシの適応を予定しています。

## エラーレスポンス、選択したアノテーションの保存

validatorから返却されたerror responseはmongodbに保存されます。同一の接続でユーザが選択したアノテーションの値についても、
返却されたエラーレスポンスと共に保存します。

### エラーレスポンスのログ（例）

    { 
    "_id" : ObjectId("570a54f421afe15a63dfc250"),
     "updateTime" : ISODate("2016-04-10T13:28:12.538Z"),
     "original_file" : "SSUB000070.xml",
     "method" : "biosample validator",
     "error_size" : 1,
     "error_res" : [ ], // エラーレスポンスをそのまま格納
     "selected" : [{attribute_name: value} ], //値が変更されたattributeとvalueのセットを格納
     "__v" : 0 
     }




