require 'net/http'
require 'json'
require 'uri'
require 'async/http/internet/instance'

module EmergeCLI
  class Network
    EMERGE_API_PROD_URL = 'api.emergetools.com'.freeze
    public_constant :EMERGE_API_PROD_URL

    RETRY_DELAY = 5
    MAX_RETRIES = 3

    def initialize(api_token:, base_url: EMERGE_API_PROD_URL)
      @base_url = base_url
      @api_token = api_token
      @internet = Async::HTTP::Internet.new
    end

    def get(path:, headers: {})
      request(:get, path, nil, headers)
    end

    def post(path:, body:, headers: {})
      request(:post, path, body, headers)
    end

    def put(path:, body:, headers: {})
      request(:put, path, body, headers)
    end

    def close
      @internet.close
    end

    private

    def request(method, path, body, custom_headers)
      uri = if path.start_with?('http')
              URI.parse(path)
            else
              URI::HTTPS.build(host: @base_url, path:)
            end
      absolute_uri = uri.to_s

      headers = {
        'X-API-Token' => @api_token,
        'User-Agent' => "emerge-cli/#{EmergeCLI::VERSION}"
      }
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
        retries += 1
        if retries <= MAX_RETRIES
          delay = RETRY_DELAY * retries
          error_message = e.message
          Logger.warn "Request failed (attempt #{retries}/#{MAX_RETRIES}): #{error_message}"
          Logger.warn "Retrying in #{delay} seconds..."

          begin
            @internet.close
          rescue StandardError
            nil
          end
          @internet = Async::HTTP::Internet.new

          sleep delay
          retry
        else
          Logger.error "Request failed after #{MAX_RETRIES} attempts: #{absolute_uri} #{e.message}"
          raise e
        end
      end
    end

    def perform_request(method, absolute_uri, headers, body)
      headers ||= {}

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
