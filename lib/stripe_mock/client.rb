module StripeMock
  class Client
    attr_reader :port, :state

    def initialize(port,host='localhost')
      @port = port

      DRb.start_service
      @pipe = DRbObject.new_with_uri "druby://#{host}:#{port}"

      # Ensure client can connect to server
      timeout_wrap(5) { @pipe.ping }
      @state = 'ready'
    end

    def mock_request(method, url, api_key, params={}, headers={})
      timeout_wrap do
        @pipe.mock_request(method, url, api_key, params, headers).tap {|result|
          response, api_key = result
          if response.is_a?(Hash) && response[:error_raised] == 'invalid_request'
            raise Stripe::InvalidRequestError.new(*response[:error_params])
          end
        }
      end
    end

    def get_server_data(key)
      timeout_wrap {
        # Massage the data make this behave the same as the local StripeMock.start
        result = {}
        @pipe.get_data(key).each {|k,v| result[k] = Stripe::Util.symbolize_names(v) }
        result
      }
    end

    def error_queue
      timeout_wrap { @pipe.error_queue }
    end

    def set_server_debug(toggle)
      timeout_wrap { @pipe.set_debug(toggle) }
    end

    def server_debug?
      timeout_wrap { @pipe.debug? }
    end

    def set_server_global_id_prefix(value)
      timeout_wrap { @pipe.set_global_id_prefix(value) }
    end

    def server_global_id_prefix
      timeout_wrap { @pipe.global_id_prefix }
    end

    def generate_bank_token(recipient_params)
      timeout_wrap { @pipe.generate_bank_token(recipient_params) }
    end

    def generate_card_token(card_params)
      timeout_wrap { @pipe.generate_card_token(card_params) }
    end

    def generate_webhook_event(event_data)
      timeout_wrap { Stripe::Util.symbolize_names @pipe.generate_webhook_event(event_data) }
    end

    def destroy_resource(type, id)
      timeout_wrap { @pipe.destroy_resource(type, id) }
    end

    def clear_server_data
      timeout_wrap { @pipe.clear_data }
    end

    def close!
      self.cleanup
      StripeMock.stop_client(:clear_server_data => false)
    end

    def cleanup
      return if @state == 'closed'
      set_server_debug(false)
      @state = 'closed'
    end

    def timeout_wrap(tries=1)
      original_tries = tries
      begin
        raise ClosedClientConnectionError if @state == 'closed'
        yield
      rescue ClosedClientConnectionError
        raise
      rescue Errno::ECONNREFUSED, DRb::DRbConnError => e
        tries -= 1
        if tries > 0
          if tries == original_tries - 1
            print "Waiting for StripeMock Server.."
          else
            print '.'
          end
          sleep 1
          retry
        else
          raise StripeMock::ServerTimeoutError.new(e)
        end
      end
    end
  end

end
