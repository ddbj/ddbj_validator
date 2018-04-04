require 'net/ssh/proxy/command'

set :deploy_to, "/home/w3sw/ddbj/DDBJValidator/deploy/development"

# rbenv setting see: https://github.com/capistrano/rbenv/
set :rbenv_type, :user # :system or :user
set :rbenv_ruby, '2.2.6'
set :rbenv_path, '/home/w3sw/.anyenv/envs/rbenv'
set :rbenv_prefix, "#{fetch(:rbenv_path)}/bin/rbenv exec"
set :rbenv_map_bins, %w(rake gem bundle ruby rails)
set :rbenv_roles, :all # default value

set :unicorn_config_path, "#{shared_path}/config/unicorn.rb"
set :unicorn_pid, "#{shared_path}/tmp/pids/unicorn.pid"
set :unicorn_rack_env, 'development'

set :ssh_options, {
  forward_agent: true
}

server "172.19.16.14", #t014
  user: "w3sw",
  roles: %w{web app},
  ssh_options: {
    user: "w3sw",
    forward_agent: true,
    auth_methods: %w(publickey),
    proxy: Net::SSH::Proxy::Command::new('ssh ddbj_gw -W %h:%p')
  }

# server-based syntax
# ======================
# Defines a single server with a list of roles and multiple properties.
# You can define all roles on a single server, or split them:

# server "example.com", user: "deploy", roles: %w{app db web}, my_property: :my_value
# server "example.com", user: "deploy", roles: %w{app web}, other_property: :other_value
# server "db.example.com", user: "deploy", roles: %w{db}



# role-based syntax
# ==================

# Defines a role with one or multiple servers. The primary server in each
# group is considered to be the first unless any hosts have the primary
# property set. Specify the username and a domain or IP for the server.
# Don't use `:all`, it's a meta role.

# role :app, %w{deploy@example.com}, my_property: :my_value
# role :web, %w{user1@primary.com user2@additional.com}, other_property: :other_value
# role :db,  %w{deploy@example.com}



# Configuration
# =============
# You can set any configuration variable like in config/deploy.rb
# These variables are then only loaded and set in this stage.
# For available Capistrano configuration variables see the documentation page.
# http://capistranorb.com/documentation/getting-started/configuration/
# Feel free to add new variables to customise your setup.



# Custom SSH Options
# ==================
# You may pass any option but keep in mind that net/ssh understands a
# limited set of options, consult the Net::SSH documentation.
# http://net-ssh.github.io/net-ssh/classes/Net/SSH.html#method-c-start
#
# Global options
# --------------
#  set :ssh_options, {
#    keys: %w(/home/rlisowski/.ssh/id_rsa),
#    forward_agent: false,
#    auth_methods: %w(password)
#  }
#
# The server-based syntax can be used to override options:
# ------------------------------------
# server "example.com",
#   user: "user_name",
#   roles: %w{web app},
#   ssh_options: {
#     user: "user_name", # overrides user setting above
#     keys: %w(/home/user_name/.ssh/id_rsa),
#     forward_agent: false,
#     auth_methods: %w(publickey password)
#     # password: "please use keys"
#   }
