#
# ServerEngine
#
# Copyright (C) 2012-2013 Sadayuki Furuhashi
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
require 'socket'

module ServerEngine
  module SocketManagerUnix

    module ClientModule
      private

      def connect_peer(path)
        return UNIXSocket.new(path)
      end

      def recv(family, proto, peer, sent)
        server_class = case proto
                       when :tcp then TCPServer
                       when :udp then UDPSocket
                       else
                         raise ArgumentError, "invalid protocol: #{proto}"
                       end
        peer.recv_io(server_class)
      end

      def recv_tcp(family, peer, sent)
        recv(family, :tcp, peer, sent)
      end

      def recv_udp(family, peer, sent)
        recv(family, :udp, peer, sent)
      end
    end

    module ServerModule
      private

      def listen_tcp_new(bind_ip, port)
        sock = TCPServer.new(bind_ip.to_s, port)
        sock.listen(Socket::SOMAXCONN)  # TODO make backlog configurable if necessary
        return sock
      end

      def listen_udp_new(bind_ip, port)
        if bind_ip.ipv6?
          sock = UDPSocket.new(Socket::AF_INET6)
        else
          sock = UDPSocket.new(Socket::AF_INET)
        end
        sock.bind(bind_ip.to_s, port)
        return sock
      end

      def start_server(path)
        # return absolute path so that client can connect to this path
        # when client changed working directory
        path = File.expand_path(path)

        @server = UNIXServer.new(path)

        @thread = Thread.new do
          if Thread.current.respond_to?(:report_on_exception=)
            # TODO: make this default when ruby 2.3 or earlier are outdated
            Thread.current.report_on_exception = true
          end

          begin
            while peer = @server.accept
              Thread.new(peer, &method(:process_peer))  # process_peer calls send_socket
            end
          rescue => e
            if @server.closed?
              # ignore error raised about unix domain socket now closed in another thread
            else
              begin
                ServerEngine.dump_uncaught_error(e)
              rescue IOError => e2 # STDERR is closed or unavailable with other reasons
                raise e # Ruby runtime can show this if Thread#report_on_exception is available
              end
            end
          end
        end

        return path
      end

      def stop_server
        @tcp_sockets.reject! {|key,lsock| lsock.close; true }
        @udp_sockets.reject! {|key,usock| usock.close; true }
        @server.close unless @server.closed?
        # It cause dead lock and can't finish when joining thread using Ruby 2.1 on linux.
        @thread.join if RUBY_VERSION >= "2.2"
      end

      def send_socket(peer, pid, method, bind, port)
        sock = send(method, bind, port)  # calls listen_tcp or listen_udp

        SocketManager.send_peer(peer, nil)

        peer.send_io sock
      end
    end

  end
end
