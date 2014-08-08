require "cloud_controller/diego/messenger"
require "cloud_controller/diego/unavailable"

module VCAP::CloudController
  module Diego
    class Client
      def initialize(enabled, message_bus, service_registry, blobstore_url_generator)
        @enabled = enabled
        @message_bus = message_bus
        @service_registry = service_registry
        @blobstore_url_generator = blobstore_url_generator
        @messenger = Messenger.new(enabled, message_bus, blobstore_url_generator)
      end

      def connect!
        @service_registry.run!
      end

      def send_desire_request(app)
        @messenger.send_desire_request(app)
      end

      def send_stage_request(app)
        @messenger.send_stage_request(app)
      end

      def desire_request(app)
        @messenger.desire_request(app)
      end

      def lrp_instances(app)
        if @service_registry.tps_addrs.empty?
          raise Unavailable
        end

        address = @service_registry.tps_addrs.first
        guid = app.versioned_guid

        uri = URI("#{address}/lrps/#{guid}")
        logger.info "Requesting lrp information for #{guid} from #{address}"

        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = 10
        http.open_timeout = 10

        response = http.get(uri.path)
        raise Unavailable.new unless response.code == '200'

        logger.info "Received lrp response for #{guid}: #{response.body}"

        result = []

        tps_instances = JSON.parse(response.body)
        tps_instances.each do |instance|
          result << {
            process_guid: instance['process_guid'],
            instance_guid: instance['instance_guid'],
            index: instance['index'],
            state: instance['state'].upcase,
            since: instance['since_in_ns'].to_i / 1_000_000_000,
          }
        end

        logger.info "Returning lrp instances for #{guid}: #{result.inspect}"

        result
      rescue Errno::ECONNREFUSED => e
        raise Unavailable.new(e)
      end

      private

      def logger
        @logger ||= Steno.logger("cc.diego.client")
      end
    end
  end
end
