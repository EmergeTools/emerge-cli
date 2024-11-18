require 'test_helper'

module EmergeCLI
  module Commands
    module Upload
      class SnapshotsTest < Minitest::Test
        def setup
          @fake_network = EmergeCLI::FakeNetwork.new
          @git_result = EmergeCLI::GitResult.new(
            sha: 'abc123',
            base_sha: 'def456',
            branch: 'main',
            previous_sha: 'ghi789',
            pr_number: '123',
            repo_name: 'test-repo'
          )
          @fake_git_info_provider = FakeGitInfoProvider.new(@git_result)

          @command = EmergeCLI::Commands::Upload::Snapshots.new(
            network: @fake_network,
            git_info_provider: @fake_git_info_provider
          )

          FileUtils.mkdir_p('tmp/test_snapshots')
          ChunkyPNG::Image.new(100, 100).save('tmp/test_snapshots/test.png')
        end

        def teardown
          FileUtils.rm_rf('tmp/test_snapshots')
        end

        def test_creates_run_and_uploads_images
          options = {
            id: 'test-id',
            name: 'test-run',
            repo_name: 'test-repo',
            concurrency: 1
          }

          @command.call(image_paths: ['tmp/test_snapshots'], api_token: 'fake-token', **options)

          run_request = @fake_network.requests.find { |req| req[:path] == '/v1/snapshots/run' }
          assert_equal :post, run_request[:method]
          assert_equal 'test-id', run_request[:body][:id]
          assert_equal 'test-run', run_request[:body][:name]
          assert_equal 'abc123', run_request[:body][:sha]
          assert_equal 'def456', run_request[:body][:base_sha]
          assert_equal 'main', run_request[:body][:branch]
          assert_equal 'ghi789', run_request[:body][:previous_sha]
          assert_equal '123', run_request[:body][:pr_number]
          assert_equal 'test-repo', run_request[:body][:repo_name]

          assert @fake_network.requests.any? { |req| req[:path] == '/v1/snapshots/run/image' && req[:method] == :post },
                 'Expected to find image upload request'

          assert @fake_network.requests.any? { |req|
            req[:path] == 'https://fake-upload-url.com' && req[:method] == :put
          },
                 'Expected to find signed URL upload request'

          assert @fake_network.requests.any? { |req|
            req[:path] == '/v1/snapshots/run/finish' && req[:method] == :post
          },
                 'Expected to find finish request'
        end

        def test_overrides_git_info_with_options
          options = {
            id: 'test-id',
            name: 'test-run',
            repo_name: 'test-repo',
            sha: 'custom-sha',
            branch: 'custom-branch',
            base_sha: 'custom-base-sha',
            previous_sha: 'custom-previous-sha',
            pr_number: 'custom-pr',
            concurrency: 1
          }

          @command.call(image_paths: ['tmp/test_snapshots'], api_token: 'fake-token', **options)

          run_request = @fake_network.requests.find { |req| req[:path] == '/v1/snapshots/run' }
          assert_equal 'custom-sha', run_request[:body][:sha]
          assert_equal 'custom-branch', run_request[:body][:branch]
          assert_equal 'custom-base-sha', run_request[:body][:base_sha]
          assert_equal 'custom-previous-sha', run_request[:body][:previous_sha]
          assert_equal 'custom-pr', run_request[:body][:pr_number]
        end
      end
    end
  end
end
