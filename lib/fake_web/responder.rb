module FakeWeb
  class Responder #:nodoc:

    attr_accessor :method, :uri, :options, :times, :response_block
    KNOWN_OPTIONS = [:body, :exception, :response, :status].freeze

    def initialize(method, uri, options, times, &block)
      self.method = method
      self.uri = uri
      self.options = options
      self.times = times ? times : 1
      self.response_block = block

      if options.has_key?(:file) || options.has_key?(:string)
        print_file_string_options_deprecation_warning
        options[:body] = options.delete(:file) || options.delete(:string)
      end
    end

    def response(&block)
      if has_baked_response?
        response = baked_response
      else
        block_body, stub_uri = nil, nil
        
        if self.response_block
          # params = params_for(request)
          block_body = self.response_block.call({})
        else
          stub_uri  = "1.0"
        end
        
        code, msg = meta_information
        response  = Net::HTTPResponse.send(:response_class, code.to_s).new(stub_uri || uri, code.to_s, msg)
        response.instance_variable_set(:@body, block_body || body)
        headers_extracted_from_options.each { |name, value| response[name] = value }
      end

      response.instance_variable_set(:@read, true)
      response.extend FakeWeb::Response

      optionally_raise(response)

      yield response if block_given?

      response
    end

    private

    def headers_extracted_from_options
      options.reject {|name, _| KNOWN_OPTIONS.include?(name) }.map { |name, value|
        [name.to_s.split("_").map { |segment| segment.capitalize }.join("-"), value]
      }
    end

    def body
      return '' unless options.has_key?(:body)

      if !options[:body].include?("\0") && File.exists?(options[:body]) && !File.directory?(options[:body])
        File.read(options[:body])
      else
        options[:body]
      end
    end

    def baked_response
      resp = case options[:response]
      when Net::HTTPResponse then options[:response]
      when String
        socket = Net::BufferedIO.new(options[:response])
        r = Net::HTTPResponse.read_new(socket)

        # Store the oiriginal transfer-encoding
        saved_transfer_encoding = r.instance_eval {
          @header['transfer-encoding'] if @header.key?('transfer-encoding')
        }

        # read the body of response.
        r.instance_eval { @header['transfer-encoding'] = nil }
        r.reading_body(socket, true) {}

        # Delete the transfer-encoding key from r.@header if there wasn't one,
        # else restore the saved_transfer_encoding.
        if saved_transfer_encoding.nil?
          r.instance_eval { @header.delete('transfer-encoding') }
        else
          r.instance_eval { @header['transfer-encoding'] = saved_transfer_encoding }
        end
        r
      else raise StandardError, "Handler unimplemented for response #{options[:response]}"
      end
    end

    def has_baked_response?
      options.has_key?(:response)
    end

    def optionally_raise(response)
      return unless options.has_key?(:exception)

      case options[:exception].to_s
      when "Net::HTTPError", "OpenURI::HTTPError"
        raise options[:exception].new('Exception from FakeWeb', response)
      else
        raise options[:exception].new('Exception from FakeWeb')
      end
    end

    def meta_information
      options.has_key?(:status) ? options[:status] : [200, 'OK']
    end

    def params_for(request)
      if request.method == 'GET'
        query = URI.parse(request.path).query
        decode_params(query)
      else
        decode_params(request.body)
      end
    end

    def decode_params(encoded_params)
      if encoded_params
        UrlEncodedPairParser.new(URI.decode(encoded_params).split('&').map {|v| v.split('=')}).result
      else
        {}
      end
    end
    
    def print_file_string_options_deprecation_warning
      which = options.has_key?(:file) ? :file : :string
      $stderr.puts
      $stderr.puts "Deprecation warning: FakeWeb's :#{which} option has been renamed to :body."
      $stderr.puts "Just replace :#{which} with :body in your FakeWeb.register_uri calls."
      $stderr.puts "Called at #{caller[6]}"
    end

  end
end
