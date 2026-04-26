Rails.application.routes.draw do
  get '/up' => 'rails/health#show', as: :rails_health_check

  scope '/api' do
    # 静的ファイル (index.html / apispec/index.html / client/index.html /
    # error_*.json) は public/api/ 配下に置いて ActionDispatch::Static に
    # 任せる。送信元: URL → ファイルのマッピングは Static が .html や
    # index.html を自動補完するのでルート定義は不要。

    post 'validation'                             => 'validations#create'
    get  'validation/:uuid'                       => 'validations#show',        constraints: {uuid: /[0-9a-f-]+/}
    get  'validation/:uuid/status'                => 'validations#status',      constraints: {uuid: /[0-9a-f-]+/}
    get  'validation/:uuid/:filetype'             => 'validations#file',        constraints: {uuid: /[0-9a-f-]+/, filetype: /[a-z][a-z_]*/}
    get  'validation/:uuid/:filetype/autocorrect' => 'validations#autocorrect', constraints: {uuid: /[0-9a-f-]+/, filetype: /[a-z][a-z_]*/}

    get  'submission/ids/:filetype'            => 'submissions#ids', constraints: {filetype: /[a-z][a-z_]*/}
    get  'submission/:filetype/:submission_id' => 'submissions#show', constraints: {filetype: /[a-z][a-z_]*/, submission_id: /[^\/]+/}

    get  'monitoring' => 'monitoring#show'

    get  'package_list'            => 'packages#list'
    get  'package_and_group_list'  => 'packages#list_with_groups'
    get  'attribute_list'          => 'packages#attributes'
    get  'attribute_template_file' => 'packages#attribute_template'
    get  'package_info'            => 'packages#info'
  end
end
