module RubySMB
  class Server
    # This class represents a single connected client to the server. It stores and processes connection specific related
    # information.
    class ServerClient

      require 'ruby_smb/dialect'
      require 'ruby_smb/signing'
      require 'ruby_smb/server/server_client/negotiation'
      require 'ruby_smb/server/server_client/session_setup'

      include RubySMB::Signing
      include RubySMB::Server::ServerClient::Negotiation
      include RubySMB::Server::ServerClient::SessionSetup

      attr_reader :dialect, :identity, :state, :session_key

      # @param [Server] server the server that accepted this connection
      # @param [Dispatcher::Socket] dispatcher the connection's socket dispatcher
      def initialize(server, dispatcher)
        @server = server
        @dispatcher = dispatcher
        @state = :negotiate
        @dialect = nil
        @message_id = 0
        @session_id = nil
        @session_key = nil
        @gss_authenticator = server.gss_provider.new_authenticator(self)
        @identity = nil
        @tree_connections = {}
        @preauth_integrity_hash_algorithm = nil
        @preauth_integrity_hash_value = nil
      end

      #
      # The dialects metadata definition.
      #
      # @return [Dialect::Definition]
      def metadialect
        Dialect::ALL[@dialect]
      end

      #
      # The peername of the connected socket. This is a combination of the IPv4 or IPv6 address and port number.
      #
      # @example Parse the value into an IP address
      #   ::Socket::unpack_sockaddr_in(server_client.getpeername)
      #
      # @return [String]
      def getpeername
        @dispatcher.tcp_socket.getpeername
      end

      #
      # Handle an authenticated request. This is the main handler for all requests after the connection has been
      # authenticated.
      #
      # @param [String] raw_request the request that should be handled
      def handle_authenticated(raw_request)
        response = nil

        case raw_request[0...4].unpack1('L>')
        when RubySMB::SMB1::SMB_PROTOCOL_ID
          raise NotImplementedError
        when RubySMB::SMB2::SMB2_PROTOCOL_ID
          raise NotImplementedError
        end

        if response.nil?
          disconnect!
          return
        end

        send_packet(response)
      end

      #
      # Process a GSS authentication buffer. If no buffer is specified, the request is assumed to be the first in the
      # negotiation sequence.
      #
      # @param [String, nil] buffer the request GSS request buffer that should be processed
      # @return [Gss::Provider::Result] the result of the processed GSS request
      def process_gss(buffer=nil)
        @gss_authenticator.process(buffer)
      end

      #
      # Run the processing loop to receive and handle requests. This loop runs until an exception occurs or the
      # dispatcher socket is closed.
      #
      def run
        loop do
          begin
            raw_request = recv_packet
          rescue RubySMB::Error::CommunicationError
            break
          end

          case @state
          when :negotiate
            handle_negotiate(raw_request)
          when :session_setup
            handle_session_setup(raw_request)
          when :authenticated
            handle_authenticated(raw_request)
          end

          break if @dispatcher.tcp_socket.closed?
        end
      end

      #
      # Disconnect the remote client.
      #
      def disconnect!
        @state = nil
        @dispatcher.tcp_socket.close
      end

      #
      # Receive a single SMB packet from the dispatcher.
      #
      # @return [String] the raw packet
      def recv_packet
        @dispatcher.recv_packet
      end

      #
      # Send a single SMB packet using the dispatcher. If necessary, the packet will be signed.
      #
      # @param [GenericPacket] packet the packet to send
      def send_packet(packet)
        if @state == :authenticated && @identity != Gss::Provider::IDENTITY_ANONYMOUS && !@session_key.nil?
          case metadialect.family
          when Dialect::FAMILY_SMB2
            packet = smb2_sign(packet)
          when Dialect::FAMILY_SMB3
            packet = smb3_sign(packet)
          end
        end

        @dispatcher.send_packet(packet)
      end

      #
      # Update the preauth integrity hash as used by dialect 3.1.1 for various cryptographic operations. The algorithm
      # and hash values must have been initialized prior to calling this.
      #
      # @param [String] data the data with which to update the preauth integrity hash
      def update_preauth_hash(data)
        unless @preauth_integrity_hash_algorithm
          raise RubySMB::Error::EncryptionError.new(
            'Cannot compute the Preauth Integrity Hash value: Preauth Integrity Hash Algorithm is nil'
          )
        end
        @preauth_integrity_hash_value = OpenSSL::Digest.digest(
          @preauth_integrity_hash_algorithm,
          @preauth_integrity_hash_value + data.to_binary_s
        )
      end
    end
  end
end
