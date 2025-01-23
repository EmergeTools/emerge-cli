require_relative 'lib/version'

Gem::Specification.new do |spec|
  spec.name          = 'emerge'
  spec.version       = EmergeCLI::VERSION
  spec.authors       = ['Emerge Tools']
  spec.email         = ['support@emergetools.com']

  spec.summary       = 'Emerge CLI'
  spec.description   = 'The official CLI for Emerge Tools'
  spec.homepage      = 'https://github.com/EmergeTools/emerge-cli'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be included in the gem when published
  spec.files = Dir[
    'lib/**/*',
    'parsers/**/*',
    'LICENSE.txt',
    'README.md',
    'CHANGELOG.md'
  ]

  spec.bindir        = 'exe'
  spec.executables   = ['emerge']
  spec.require_paths = ['lib']

  spec.add_dependency 'async-http', '~> 0.86.0'
  spec.add_dependency 'CFPropertyList', '~> 2.3', '>= 2.3.2'
  spec.add_dependency 'chunky_png', '~> 1.4.0'
  spec.add_dependency 'dry-cli', '~> 1.2.0'
  spec.add_dependency 'open3', '~> 0.2.1'
  spec.add_dependency 'ruby-macho', '~> 4.1.0'
  spec.add_dependency 'ruby_tree_sitter', '~> 1.9'
  spec.add_dependency 'rubyzip', '~> 2.3.0'
  spec.add_dependency 'tty-prompt', '~> 0.23.1'
  spec.add_dependency 'tty-table', '~> 0.12.0'
  spec.add_dependency 'xcodeproj', '~> 1.27.0'
  spec.add_dependency 'nkf', '~> 0.1.3'
  spec.add_dependency 'base64', '~> 0.2.0'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
