require_relative 'lib/version'

Gem::Specification.new do |spec|
  spec.name          = 'emerge'
  spec.version       = EmergeCli::VERSION
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
    'LICENSE.txt',
    'README.md',
    'CHANGELOG.md'
  ]

  spec.bindir        = 'exe'
  spec.executables   = ['emerge']
  spec.require_paths = ['lib']

  spec.add_dependency 'async', '~> 2.20.0'
  spec.add_dependency 'async-http', '~> 0.83.1'
  spec.add_dependency 'chunky_png', '~> 1.4.0'
  spec.add_dependency 'dry-cli', '~> 1.2.0'
  spec.add_dependency 'open3', '~> 0.2.1'
  spec.add_dependency 'pry-byebug', '~> 3.8'
  spec.add_dependency 'ruby_tree_sitter', '~> 1.9'
  spec.add_dependency 'tty-prompt', '~> 0.23.1'
  spec.add_dependency 'tty-table', '~> 0.12.0'
  spec.add_dependency 'xcodeproj', '~> 1.27.0'

  spec.add_development_dependency 'minitest', '~> 5.25.1'
  spec.add_development_dependency 'minitest-reporters', '~> 1.7.1'
  spec.add_development_dependency 'pry', '~> 0.15.0'
  spec.add_development_dependency 'rake', '~> 13.2.1'
  spec.add_development_dependency 'rspec', '~> 3.13.0'
  spec.add_development_dependency 'rubocop', '~> 1.68.0'
  spec.add_development_dependency 'simplecov', '~> 0.22.0'
end
