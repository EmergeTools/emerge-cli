require_relative './commands/global_options'
require_relative './commands/reaper/reaper'
require_relative './commands/upload/snapshots/snapshots'
require_relative './commands/upload/snapshots/client_libraries/swift_snapshot_testing'
require_relative './commands/upload/snapshots/client_libraries/paparazzi'
require_relative './commands/upload/snapshots/client_libraries/roborazzi'
require_relative './commands/upload/snapshots/client_libraries/default'
require_relative './commands/integrate/fastlane'
require_relative './commands/config/snapshots/snapshots_ios'
require_relative './commands/config/orderfiles/orderfiles_ios'

require_relative './utils/git_info_provider'
require_relative './utils/git_result'
require_relative './utils/github'
require_relative './utils/git'
require_relative './utils/logger'
require_relative './utils/network'
require_relative './utils/profiler'
require_relative './utils/project_detector'

require 'dry/cli'

module EmergeCLI
  extend Dry::CLI::Registry

  register 'upload', aliases: ['u'] do |prefix|
    prefix.register 'snapshots', Commands::Upload::Snapshots
  end

  register 'integrate' do |prefix|
    prefix.register 'fastlane-ios', Commands::Integrate::Fastlane, aliases: ['i']
  end

  register 'configure' do |prefix|
    prefix.register 'snapshots-ios', Commands::Config::SnapshotsIOS
    prefix.register 'order-files-ios', Commands::Config::OrderFilesIOS
  end
end

# By default the log level is INFO, but can be overridden by the --debug flag
EmergeCLI::Logger.configure(::Logger::INFO)
