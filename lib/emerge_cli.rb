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
require_relative 'commands/upload/snapshots/snapshots'
require_relative 'commands/upload/snapshots/client_libraries/swift_snapshot_testing'
require_relative 'commands/upload/snapshots/client_libraries/paparazzi'
require_relative 'commands/upload/snapshots/client_libraries/roborazzi'
require_relative 'commands/upload/snapshots/client_libraries/default'
require_relative 'commands/test'

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

  register 'test', Commands::Test

  register 'configure' do |prefix|
    prefix.register 'snapshots-ios', Commands::Config::SnapshotsIOS
    prefix.register 'order-files-ios', Commands::Config::OrderFilesIOS
  end

  register 'download' do |prefix|
    prefix.register 'order-files', Commands::OrderFiles::Download
  end

  register 'fix' do |prefix|
    prefix.register 'minify-strings', Commands::Fix::MinifyStrings
    prefix.register 'strip-binary-symbols', Commands::Fix::StripBinarySymbols
    prefix.register 'exported-symbols', Commands::Fix::ExportedSymbols
  end

  register 'integrate' do |prefix|
    prefix.register 'fastlane-ios', Commands::Integrate::Fastlane, aliases: ['i']
  end

  register 'install' do |prefix|
    prefix.register 'build', Commands::Build::Distribution::Install
  end

  # TODO: make this command action oriented
  register 'reaper', Commands::Reaper

  register 'upload', aliases: ['u'] do |prefix|
    prefix.register 'build', Commands::Upload::Build
    prefix.register 'snapshots', Commands::Upload::Snapshots
  end

  register 'validate' do |prefix|
    prefix.register 'build-distribution', Commands::Build::Distribution::ValidateApp
    prefix.register 'order-files-linkmaps', Commands::OrderFiles::ValidateLinkmaps
    prefix.register 'order-files-xcode-project', Commands::OrderFiles::ValidateXcodeProject
    prefix.register 'snapshots-app-ios', Commands::Snapshots::ValidateApp
  end
end

# By default the log level is INFO, but can be overridden by the --debug flag
EmergeCLI::Logger.configure(Logger::INFO)

# Add this at the end of the file
Dry::CLI.new(EmergeCLI).call if $PROGRAM_NAME == __FILE__
