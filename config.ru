require 'rack'
require './app/application.rb'

if defined?(Unicorn)
  require 'unicorn/worker_killer'
  use Unicorn::WorkerKiller::MaxRequests, 1000, 2000
end
run DDBJValidator::Application
