Rails.application.routes.draw do
  get '/up' => 'rails/health#show', as: :rails_health_check

  scope '/api' do
    get  ''                                       => 'api#index'
    get  'apispec/'                               => 'api#apispec'
    get  'client/index'                           => 'api#client'

    post 'validation'                             => 'api#validation_create'
    get  'validation/:uuid'                       => 'api#validation_show',        uuid: /[0-9a-f-]+/
    get  'validation/:uuid/status'                => 'api#validation_status',      uuid: /[0-9a-f-]+/
    get  'validation/:uuid/:filetype'             => 'api#validation_file',        uuid: /[0-9a-f-]+/
    get  'validation/:uuid/:filetype/autocorrect' => 'api#validation_autocorrect', uuid: /[0-9a-f-]+/

    get  'submission/ids/:filetype'               => 'api#submission_ids'
    get  'submission/:filetype/:submission_id'    => 'api#submission_show',        submission_id: /[^\/]+/

    get  'monitoring'                             => 'api#monitoring'

    get  'package_list'                           => 'api#package_list'
    get  'package_and_group_list'                 => 'api#package_and_group_list'
    get  'attribute_list'                         => 'api#attribute_list'
    get  'attribute_template_file'                => 'api#attribute_template_file'
    get  'package_info'                           => 'api#package_info'

    get  'error_unauthorized.json'                => 'api#error_unauthorized'
    get  'error_forbidden.json'                   => 'api#error_forbidden'
    get  'error_not_found.json'                   => 'api#error_not_found'
  end
end
