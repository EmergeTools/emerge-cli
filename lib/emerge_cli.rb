require_relative 'version'

require_relative 'commands/global_options'
require_relative 'commands/build/distribution/validate'
require_relative 'commands/build/distribution/install'
require_relative 'commands/config/snapshots/snapshots_ios'
require_relative 'commands/config/orderfiles/orderfiles_ios'
require_relative 'commands/integrate/fastlane'
require_relative 'commands/fix/minify_strings'
require_relative 'commands/fix/strip_binary_symbols'
require_relative 'commands/fix/exported_symbols'
require_relative 'commands/order_files/download_order_files'
require_relative 'commands/order_files/validate_linkmaps'
require_relative 'commands/order_files/validate_xcode_project'
require_relative 'commands/reaper/reaper'
require_relative 'commands/snapshots/validate_app'
require_relative 'commands/upload/build'
require_relative 'commands/upload/snapshots'
require_relative 'commands/upload/snapshots/upload'
require_relative 'commands/upload/snapshots/client_libraries/swift_snapshot_testing'
require_relative 'commands/upload/snapshots/client_libraries/paparazzi'
require_relative 'commands/upload/snapshots/client_libraries/roborazzi'
require_relative 'commands/upload/snapshots/client_libraries/default'

require_relative 'reaper/ast_parser'
require_relative 'reaper/code_deleter'

require_relative 'utils/environment'
require_relative 'utils/git_info_provider'
require_relative 'utils/git_result'
require_relative 'utils/github'
require_relative 'utils/git'
require_relative 'utils/logger'
require_relative 'utils/network'
require_relative 'utils/profiler'
require_relative 'utils/project_detector'
require_relative 'utils/macho_parser'
require_relative 'utils/version_check'
require_relative 'utils/xcode_device_manager'
require_relative 'utils/xcode_simulator'
require_relative 'utils/xcode_physical_device'

require 'dry/cli'

module EmergeCLI
  extend Dry::CLI::Registry

  register 'build' do |prefix|
    prefix.register 'install', Commands::Build::Distribution::Install
    prefix.register 'validate', Commands::Build::Distribution::Validate
  end

  register 'configure' do |prefix|
    prefix.register 'snapshots-ios', Commands::Config::SnapshotsIOS
    prefix.register 'order-files-ios', Commands::Config::OrderFilesIOS
  end

  register 'fix' do |prefix|
    prefix.register 'minify-strings', Commands::Fix::MinifyStrings
    prefix.register 'strip-binary-symbols', Commands::Fix::StripBinarySymbols
    prefix.register 'exported-symbols', Commands::Fix::ExportedSymbols
  end

  register 'integrate' do |prefix|
    prefix.register 'fastlane-ios', Commands::Integrate::Fastlane, aliases: ['i']
  end

  register 'order-files' do |prefix|
    prefix.register 'download', Commands::OrderFiles::Download
    prefix.register 'validate-linkmaps', Commands::OrderFiles::ValidateLinkmaps
    prefix.register 'validate-xcode-project', Commands::OrderFiles::ValidateXcodeProject
  end

  register 'reaper', Commands::Reaper

  register 'snapshots', aliases: ['s'] do |prefix|
    prefix.register 'validate-app-ios', Commands::Snapshots::ValidateApp
  end

  # Deprecated, for backwards compatibility
  register 'upload', aliases: ['u'] do |prefix|
    prefix.register 'build', Commands::Build::Upload
    prefix.register 'snapshots', Commands::Snapshots::Upload
  end
end

# By default the log level is INFO, but can be overridden by the --debug flag
EmergeCLI::Logger.configure(Logger::INFO)
