require 'test_helper'

module EmergeCLI
  module Commands
    class DownloadOrderFilesTest < Minitest::Test
      def teardown
        FileUtils.remove_entry 'com.emerge.hn.Hacker-News-3.4.0.gz'
        FileUtils.remove_entry 'com.emerge.hn.Hacker-News-3.4.0'
      end

      def test_unzips_file_when_unzip_flag_is_true
        @network = FakeNetwork.new(
          '/com.emerge.hn.Hacker-News/3.4.0' => File.read('test/test_files/com.emerge.hn.Hacker-News-3.4.0.gz')
        )
        @download_order_files = OrderFiles::Download.new(network: @network)

        options = {
          bundle_id: 'com.emerge.hn.Hacker-News',
          app_version: '3.4.0',
          unzip: true,
          api_token: 'example_token'
        }

        @download_order_files.call(**options)

        assert_equal 1, Dir.glob('com.emerge.hn.Hacker-News-3.4.0').length

        content = File.read('com.emerge.hn.Hacker-News-3.4.0')
        expected = "+[SentryAppStartTracker load]\n"
        assert_equal expected, content.lines.first
      end
    end
  end
end
