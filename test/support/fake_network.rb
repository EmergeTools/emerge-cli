module EmergeCLI
  class FakeNetwork
    DEFAULT_RESPONSES = {
      '/v1/snapshots/run' => { 'run_id' => 'fake-run-id' }.to_json,
      '/v1/snapshots/run/image' => { 'image_url' => 'https://fake-upload-url.com' }.to_json,
      '/v1/snapshots/run/finish' => '{}',
      'https://fake-upload-url.com' => ''
    }.freeze

    def initialize(responses = {})
      @responses = DEFAULT_RESPONSES.merge(responses)
      @requests = []
    end

    attr_reader :requests

    def get(path:, headers: nil, max_retries: 0)
      @requests << { method: :get, path:, headers:, max_retries: }
      response_for(path)
    end

    def post(path:, body: nil, headers: nil, max_retries: 0)
      @requests << { method: :post, path:, body:, headers:, max_retries: }
      response_for(path)
    end

    def put(path:, body: nil, headers: nil, max_retries: 0)
      @requests << { method: :put, path:, body:, headers:, max_retries: }
      response_for(path)
    end

    def close
      # No-op for fake
    end

    private

    def response_for(path)
      raise "No fake response configured for path: #{path}" unless @responses.key?(path)

      response_content = @responses[path]
      case response_content
      when StandardError
        raise response_content
      else
        FakeResponse.new(response_content)
      end
    end
  end

  class FakeResponse
    def initialize(body)
      @body = body
    end

    def read
      @body
    end
  end
end
