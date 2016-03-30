# About DDBJ BioSample Validator

## システム仕様

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



## インストールと起動


