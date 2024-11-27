require 'net/http'
require 'json'
require 'uri'
require 'async/http/internet/instance'

module EmergeCLI
  class Network
    EMERGE_API_PROD_URL = 'api.emergetools.com'.freeze
    public_constant :EMERGE_API_PROD_URL

    RETRY_DELAY = 5
    MAX_RETRIES = 1

    def initialize(api_token:, base_url: EMERGE_API_PROD_URL)
      @base_url = base_url
      @api_token = api_token
      @internet = Async::HTTP::Internet.new
    end

    def get(path:, headers: {})
      request(:get, path, nil, headers)
    end

    def post(path:, body:, headers: {}, query: nil)
      request(:post, path, body, headers, query)
    end

    def put(path:, body:, headers: {})
      request(:put, path, body, headers)
    end

    def close
      @internet.close
    end

    private

    def request(method, path, body, custom_headers, query = nil)
      uri = if path.start_with?('http')
              URI.parse(path)
            else
              query_string = query ? URI.encode_www_form(query) : nil
              URI::HTTPS.build(
                host: @base_url,
                path: path,
                query: query_string
              )
            end
      absolute_uri = uri.to_s

      headers = { 'X-API-Token' => @api_token }
      headers['Content-Type'] = 'application/json' if method == :post && body.is_a?(Hash)
      headers.merge!(custom_headers)

      body = JSON.dump(body) if body.is_a?(Hash) && method == :post

      Logger.debug "Request: #{method} #{truncate_uri(absolute_uri)} #{method == :post ? body : 'N/A'}"

      retries = 0
      begin
        response = perform_request(method, absolute_uri, headers, body)

        unless response.success?
          Logger.error "Request failed: #{absolute_uri} #{response}"
          raise "Request failed: #{absolute_uri} #{response}"
        end

        response
      rescue StandardError => e
        # Workaround for an issue where the request is not fully written, haven't determined the root cause yet
        if e.message.include?('Wrote 0 bytes') && retries < MAX_RETRIES
          retries += 1
          Logger.warn "Request failed due to incomplete write. Retrying in #{RETRY_DELAY} seconds..."
          sleep RETRY_DELAY
          retry
        else
          Logger.error "Request failed: #{absolute_uri} #{e.message}"
          raise e
        end
      end
    end

    def perform_request(method, absolute_uri, headers, body)
      case method
      when :get
        @internet.get(absolute_uri, headers:)
      when :post
        @internet.post(absolute_uri, headers:, body:)
      when :put
        @internet.put(absolute_uri, headers:, body:)
      else
        raise "Unsupported method: #{method}"
      end
    end

    def truncate_uri(uri, max_length = 100)
      uri.length > max_length ? "#{uri[0..max_length]}..." : uri
    end
  end
end
