require 'simplecov'
require 'minitest/autorun'
require 'minitest/pride'
require 'minitest/reporters'
require 'tmpdir'
require 'fileutils'

require_relative 'support/fake_network'
require_relative 'support/fake_git_info_provider'

# Use the Progress Reporter for CI, otherwise use the Default Reporter
reporter_options = { detailed_skip: false, color: true }
Minitest::Reporters.use!(
  if ENV['MINITEST_REPORTER']
    Minitest::Reporters.const_get(ENV['MINITEST_REPORTER']).new(reporter_options)
  else
    Minitest::Reporters::DefaultReporter.new(reporter_options)
  end
)

SimpleCov.start do
  add_filter '/test/'
  add_filter '/vendor/'

  add_group 'Commands', 'lib/commands'
  add_group 'Utils', 'lib/utils'

  enable_coverage :branch
end

require_relative '../lib/emerge_cli'

# Ensure fixtures directory exists
FIXTURES_ROOT = File.expand_path('fixtures', __dir__)
Dir.mkdir(FIXTURES_ROOT) unless File.directory?(FIXTURES_ROOT)
