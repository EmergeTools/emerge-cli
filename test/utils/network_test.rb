require 'test_helper'

module EmergeCLI
  class NetworkTest < Minitest::Test
    def test_redact_uri_removes_query_string
      url = 'https://uploads.example.com/runs/abc/batch.zip?CREDENTIALS_WOULD_BE_HERE'

      redacted = Network.redact_uri(url)

      assert_equal 'https://uploads.example.com/runs/abc/batch.zip?[REDACTED]', redacted
      refute_includes redacted, 'CREDENTIALS_WOULD_BE_HERE'
    end

    def test_redact_uri_leaves_uri_without_query_unchanged
      url = 'https://api.example.com/v1/snapshots/run/batch-image'

      assert_equal url, Network.redact_uri(url)
    end

    def test_redact_uri_accepts_uri_objects
      uri = URI.parse('https://uploads.example.com/object?SIGNATURE_WOULD_BE_HERE')

      assert_equal 'https://uploads.example.com/object?[REDACTED]', Network.redact_uri(uri)
    end
  end
end
