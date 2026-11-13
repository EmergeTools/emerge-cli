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

    def initialize(api_token: nil, base_url: EMERGE_API_PROD_URL)
      @base_url = base_url
      @api_token = api_token
      @internet = Async::HTTP::Internet.new
    end

    def get(path:, headers: {}, query: nil, max_retries: MAX_RETRIES)
      request(:get, path, nil, headers, query, max_retries)
    end

    def post(path:, body:, headers: {}, query: nil, max_retries: MAX_RETRIES)
      request(:post, path, body, headers, query, max_retries)
    end

    def put(path:, body:, headers: {}, max_retries: MAX_RETRIES)
      request(:put, path, body, headers, nil, max_retries)
    end

    def close
      @internet.close
    end

    # Returns the URI with its query string replaced, so it is safe to log.
    def self.redact_uri(uri)
      uri_string = uri.to_s
      query_start = uri_string.index('?')
      return uri_string unless query_start

      "#{uri_string[0...query_start]}?[REDACTED]"
    end

    private

    def request(method, path, body, custom_headers, query = nil, max_retries = MAX_RETRIES)
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
      # Never log the query string: presigned upload URLs carry signatures and
      # temporary credentials there, and CLI output often ends up in public CI logs.
      loggable_uri = self.class.redact_uri(absolute_uri)

      headers = {
        'User-Agent' => "emerge-cli/#{EmergeCLI::VERSION}"
      }
      headers['X-API-Token'] = @api_token if @api_token
      headers['Content-Type'] = 'application/json' if method == :post && body.is_a?(Hash)
      headers.merge!(custom_headers)

      body = JSON.dump(body) if body.is_a?(Hash) && method == :post

      Logger.debug "Request: #{method} #{truncate_uri(loggable_uri)} #{method == :post ? body : 'N/A'}"

      retries = 0
      begin
        response = perform_request(method, absolute_uri, headers, body)

        unless response.success?
          Logger.error "Request failed: #{loggable_uri} #{response}"
          raise "Request failed: #{loggable_uri} #{response}"
        end

        response
      rescue StandardError => e
        retries += 1
        if retries <= max_retries
          delay = RETRY_DELAY * retries
          error_message = e.message
          Logger.warn "Request failed (attempt #{retries}/#{max_retries}): #{error_message}"
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
          unless max_retries == 0
            Logger.error "Request failed after #{max_retries} attempts: #{loggable_uri} #{e.message}"
          end
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
