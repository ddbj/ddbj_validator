require_relative 'test_helpers'

Dir.glob(File.expand_path('**/*_test.rb', __dir__)).sort.each do |test|
  require test
end
