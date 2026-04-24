Rails.application.routes.draw do
  get '/up' => 'rails/health#show', as: :rails_health_check

  scope '/api' do
    get  ''                                       => 'home#index'
    get  'apispec/'                               => 'home#apispec'
    get  'client/index'                           => 'home#client'
    get  'error_unauthorized.json'                => 'home#error_unauthorized'
    get  'error_forbidden.json'                   => 'home#error_forbidden'
    get  'error_not_found.json'                   => 'home#error_not_found'

    post 'validation'                             => 'validations#create'
    get  'validation/:uuid'                       => 'validations#show',     uuid: /[0-9a-f-]+/
    get  'validation/:uuid/status'                => 'validations#status',   uuid: /[0-9a-f-]+/
    get  'validation/:uuid/:filetype'             => 'validations#file',     uuid: /[0-9a-f-]+/
    get  'validation/:uuid/:filetype/autocorrect' => 'validations#autocorrect', uuid: /[0-9a-f-]+/

    get  'submission/ids/:filetype'               => 'submissions#ids'
    get  'submission/:filetype/:submission_id'    => 'submissions#show',     submission_id: /[^\/]+/

    get  'monitoring'                             => 'monitoring#show'

    get  'package_list'                           => 'packages#list'
    get  'package_and_group_list'                 => 'packages#list_with_groups'
    get  'attribute_list'                         => 'packages#attributes'
    get  'attribute_template_file'                => 'packages#attribute_template'
    get  'package_info'                           => 'packages#info'
  end
end
