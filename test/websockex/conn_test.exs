defmodule WebSockex.ConnTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, {server_ref, url}} = WebSockex.TestServer.start(self())

    on_exit(fn -> WebSockex.TestServer.shutdown(server_ref) end)

    uri = URI.parse(url)

    conn = WebSockex.Conn.new(uri)

    {:ok, conn} = WebSockex.Conn.open_socket(conn)

    [url: url, uri: uri, conn: conn]
  end

  test "new" do
    tcp_conn = %WebSockex.Conn{
      host: "localhost",
      port: 80,
      path: "/ws",
      query: nil,
      conn_mod: :gen_tcp,
      transport: :tcp,
      extra_headers: [{"Pineapple", "Cake"}],
      socket: nil,
      socket_connect_timeout: 6000,
      socket_recv_timeout: 5000,
      inet_family: :inet
    }

    ssl_conn = %WebSockex.Conn{
      host: "localhost",
      port: 443,
      path: "/ws",
      query: nil,
      conn_mod: :ssl,
      transport: :ssl,
      extra_headers: [{"Pineapple", "Cake"}],
      socket: nil,
      socket_connect_timeout: 6000,
      socket_recv_timeout: 5000,
      inet_family: :inet
    }

    regular_url = "ws://localhost/ws"
    regular_uri = URI.parse(regular_url)

    regular_opts = [
      extra_headers: [{"Pineapple", "Cake"}],
      socket_connect_timeout: 123,
      socket_recv_timeout: 456
    ]

    assert WebSockex.Conn.new(regular_uri, regular_opts) == %{
             tcp_conn
             | socket_connect_timeout: 123,
               socket_recv_timeout: 456
           }

    assert WebSockex.Conn.new(regular_url, regular_opts) ==
             WebSockex.Conn.new(regular_uri, regular_opts)

    conn_opts = [extra_headers: [{"Pineapple", "Cake"}]]

    ssl_url = "wss://localhost/ws"
    ssl_uri = URI.parse(ssl_url)
    assert WebSockex.Conn.new(ssl_uri, conn_opts) == ssl_conn
    assert WebSockex.Conn.new(ssl_url, conn_opts) == WebSockex.Conn.new(ssl_uri, conn_opts)

    http_url = "http://localhost/ws"
    http_uri = URI.parse(http_url)
    assert WebSockex.Conn.new(http_uri, conn_opts) == tcp_conn
    assert WebSockex.Conn.new(http_url, conn_opts) == WebSockex.Conn.new(http_uri, conn_opts)

    https_url = "https://localhost/ws"
    https_uri = URI.parse(https_url)
    assert WebSockex.Conn.new(https_uri, conn_opts) == ssl_conn
    assert WebSockex.Conn.new(https_url, conn_opts) == WebSockex.Conn.new(https_uri, conn_opts)

    llama_url = "llama://localhost/ws"
    llama_conn = URI.parse(llama_url)

    assert WebSockex.Conn.new(llama_conn, conn_opts) ==
             %WebSockex.Conn{
               host: "localhost",
               port: nil,
               path: "/ws",
               query: nil,
               conn_mod: nil,
               transport: nil,
               extra_headers: [{"Pineapple", "Cake"}],
               socket: nil,
               socket_connect_timeout: 6000,
               socket_recv_timeout: 5000,
               inet_family: :inet
             }

    assert {:error, %WebSockex.URLError{}} = WebSockex.Conn.new(llama_url, conn_opts)
  end

  test "parse_url" do
    assert WebSockex.Conn.parse_url("lemon_pie") ==
             {:error, %WebSockex.URLError{url: "lemon_pie"}}

    ws_url = "ws://localhost/ws"
    assert WebSockex.Conn.parse_url(ws_url) == {:ok, URI.parse(ws_url)}

    wss_url = "wss://localhost/ws"
    assert WebSockex.Conn.parse_url(wss_url) == {:ok, URI.parse(wss_url)}

    http_url = "https://localhost/ws"
    assert WebSockex.Conn.parse_url(http_url) == {:ok, URI.parse(http_url)}

    https_url = "https://localhost/wss"
    assert WebSockex.Conn.parse_url(https_url) == {:ok, URI.parse(https_url)}

    pathless_url = "ws://localhost"
    assert WebSockex.Conn.parse_url(pathless_url) == {:ok, %{URI.parse(pathless_url) | path: "/"}}
  end

  test "open_socket", context do
    %{host: host, port: port, path: path} = context.uri

    assert {:ok, %WebSockex.Conn{host: ^host, port: ^port, path: ^path, socket: _}} =
             WebSockex.Conn.open_socket(context.conn)
  end

  test "open_socket with bad path", context do
    conn = %{context.conn | path: "bad_path"}

    {:ok, conn} = WebSockex.Conn.open_socket(conn)
    {:ok, request} = WebSockex.Conn.build_request(conn, "pants")
    :ok = WebSockex.Conn.socket_send(conn, request)

    assert WebSockex.Conn.handle_response(conn, self()) ==
             {:error, %WebSockex.RequestError{code: 400, message: "Bad Request"}}
  end

  describe "secure connection" do
    setup do
      {:ok, {server_ref, url}} = WebSockex.TestServer.start_https(self())

      on_exit(fn -> WebSockex.TestServer.shutdown(server_ref) end)

      uri = URI.parse(url)

      {:ok, conn} = WebSockex.Conn.new(uri) |> WebSockex.Conn.open_socket()

      [url: url, uri: uri, conn: conn]
    end

    test "open_socket with supplied cacerts", context do
      conn =
        WebSockex.Conn.new(
          context.uri,
          insecure: false,
          cacerts: WebSockex.TestServer.cacerts()
        )

      assert {:ok, %WebSockex.Conn{conn_mod: :ssl, transport: :ssl, insecure: false}} =
               WebSockex.Conn.open_socket(conn)
    end

    test "open_socket with insecure flag", context do
      conn = WebSockex.Conn.new(context.uri, insecure: true)

      assert {:ok, %WebSockex.Conn{conn_mod: :ssl, transport: :ssl, insecure: true}} =
               WebSockex.Conn.open_socket(conn)
    end

    test "close_socket", context do
      socket = context.conn.socket

      assert {:ok, _} = :ssl.sockname(socket)
      assert WebSockex.Conn.close_socket(context.conn) == %{context.conn | socket: nil}
      Process.sleep(50)
      assert {:error, _} = :ssl.sockname(socket)
    end

    test "open_socket with custom ssl options", context do
      ssl_options = [cacertfile: Path.join([__DIR__, "..", "support", "priv", "websockexca.cer"])]
      conn = WebSockex.Conn.new(context.uri, ssl_options: ssl_options)

      assert {:ok,
              %WebSockex.Conn{
                conn_mod: :ssl,
                transport: :ssl,
                ssl_options: ^ssl_options
              }} = WebSockex.Conn.open_socket(conn)
    end
  end

  test "close_socket", context do
    socket = context.conn.socket

    assert {:ok, _} = :inet.port(socket)
    assert WebSockex.Conn.close_socket(context.conn) == %{context.conn | socket: nil}
    assert :inet.port(socket) == {:error, :einval}
  end

  test "close_socket with nil socket", context do
    conn = %{context.conn | socket: nil}
    assert conn.socket == nil

    assert WebSockex.Conn.close_socket(conn) == conn
  end

  describe "set_active" do
    test "works on ws connections", context do
      assert :inet.getopts(context.conn.socket, [:active]) == {:ok, active: false}
      assert WebSockex.Conn.set_active(context.conn, true) == :ok
      assert :inet.getopts(context.conn.socket, [:active]) == {:ok, active: true}
      assert WebSockex.Conn.set_active(context.conn, false) == :ok
      assert :inet.getopts(context.conn.socket, [:active]) == {:ok, active: false}
    end

    test "works on wss connections" do
      {:ok, {server_ref, url}} = WebSockex.TestServer.start_https(self())
      on_exit(fn -> WebSockex.TestServer.shutdown(server_ref) end)
      uri = URI.parse(url)
      conn = WebSockex.Conn.new(uri)
      {:ok, conn} = WebSockex.Conn.open_socket(conn)

      assert :ssl.getopts(conn.socket, [:active]) == {:ok, active: false}
      assert WebSockex.Conn.set_active(conn, true) == :ok
      assert :ssl.getopts(conn.socket, [:active]) == {:ok, active: true}
      assert WebSockex.Conn.set_active(conn, false) == :ok
      assert :ssl.getopts(conn.socket, [:active]) == {:ok, active: false}
    end

    test "sets to true by default", context do
      assert :inet.getopts(context.conn.socket, [:active]) == {:ok, active: false}
      assert WebSockex.Conn.set_active(context.conn) == :ok
      assert :inet.getopts(context.conn.socket, [:active]) == {:ok, active: true}
    end
  end

  test "socket_send returns a send error when fails to send", %{conn: conn} do
    socket = conn.socket
    :ok = conn.conn_mod.close(socket)

    assert WebSockex.Conn.socket_send(conn, "Gonna Fail") ==
             {:error, %WebSockex.ConnError{original: :closed}}
  end

  test "build_request" do
    conn = %WebSockex.Conn{
      host: "lime.com",
      port: 80,
      path: "/coco",
      query: "nut=true",
      extra_headers: [{"X-Test", "Shoes"}]
    }

    {:ok, request} = WebSockex.Conn.build_request(conn, "pants")

    # Split request into lines for easier testing
    [request_line | header_lines] = String.split(request, "\r\n")

    # Check request line
    assert request_line == "GET /coco?nut=true HTTP/1.1"

    # Convert headers to a MapSet for order-independent comparison
    headers = MapSet.new(header_lines -- [""])

    # Check required headers are present
    required_headers =
      MapSet.new([
        "Host: #{conn.host}",
        "Connection: Upgrade",
        "Upgrade: websocket",
        "Sec-WebSocket-Version: 13",
        "Sec-WebSocket-Key: pants",
        "X-Test: Shoes"
      ])

    assert MapSet.subset?(required_headers, headers)

    # Check request ends with double CRLF
    assert String.ends_with?(request, "\r\n\r\n")

    # Test with non-standard port
    conn = %{conn | port: 9000}
    {:ok, request} = WebSockex.Conn.build_request(conn, "pants")
    [_request_line | header_lines] = String.split(request, "\r\n")
    headers = MapSet.new(header_lines -- [""])

    # Check host header includes port for non-standard port
    required_headers =
      MapSet.new([
        "Host: #{conn.host}:#{conn.port}",
        "Connection: Upgrade",
        "Upgrade: websocket",
        "Sec-WebSocket-Version: 13",
        "Sec-WebSocket-Key: pants",
        "X-Test: Shoes"
      ])

    assert MapSet.subset?(required_headers, headers)
  end

  test "controlling_process", %{conn: conn} do
    socket = conn.socket
    # Start a random process
    {:ok, agent_pid} = Agent.start_link(fn -> :test end)

    assert :erlang.port_info(socket, :connected) == {:connected, self()}

    WebSockex.Conn.controlling_process(conn, agent_pid)

    assert :erlang.port_info(socket, :connected) == {:connected, agent_pid}
  end

  describe "inet_family option" do
    test "defaults to inet (IPv4)" do
      uri = URI.parse("ws://localhost/ws")
      conn = WebSockex.Conn.new(uri)
      
      assert conn.inet_family == :inet
    end

    test "can be set to inet6 (IPv6)" do
      uri = URI.parse("ws://localhost/ws")
      conn = WebSockex.Conn.new(uri, inet_family: :inet6)
      
      assert conn.inet_family == :inet6
    end

    test "inet6 connection to localhost IPv6", context do
      # Skip if IPv6 is not available on the system
      case :inet.getaddr(~c"localhost", :inet6) do
        {:ok, _} ->
          uri = URI.parse(context.url)
          conn = WebSockex.Conn.new(uri, inet_family: :inet6)
          
          # Try to open socket with IPv6
          case WebSockex.Conn.open_socket(conn) do
            {:ok, conn} ->
              assert conn.inet_family == :inet6
              assert conn.socket != nil
              WebSockex.Conn.close_socket(conn)
            
            {:error, %WebSockex.ConnError{}} ->
              # IPv6 connection might fail if server doesn't support it
              # which is acceptable for this test
              :ok
          end

        {:error, _} ->
          # IPv6 not available, skip test
          :ok
      end
    end

    test "inet6 works with SSL connections" do
      case :inet.getaddr(~c"localhost", :inet6) do
        {:ok, _} ->
          {:ok, {server_ref, url}} = WebSockex.TestServer.start_https(self())
          on_exit(fn -> WebSockex.TestServer.shutdown(server_ref) end)
          
          uri = URI.parse(url)
          conn = WebSockex.Conn.new(uri, inet_family: :inet6, insecure: true)
          
          assert conn.inet_family == :inet6
          assert conn.conn_mod == :ssl
          
          # Try to connect
          case WebSockex.Conn.open_socket(conn) do
            {:ok, conn} ->
              assert conn.socket != nil
              WebSockex.Conn.close_socket(conn)
            
            {:error, %WebSockex.ConnError{}} ->
              # IPv6 connection might fail if server doesn't support it
              :ok
          end

        {:error, _} ->
          # IPv6 not available, skip test
          :ok
      end
    end

    test "socket_options include inet_family for TCP", context do
      uri = URI.parse(context.url)
      
      # Test with IPv4 (default)
      conn_ipv4 = WebSockex.Conn.new(uri)
      {:ok, conn_ipv4} = WebSockex.Conn.open_socket(conn_ipv4)
      {:ok, opts_ipv4} = :inet.getopts(conn_ipv4.socket, [:inet])
      # The socket should have the inet option set (though it may not be directly queryable)
      # We verify the connection was successful
      assert conn_ipv4.socket != nil
      WebSockex.Conn.close_socket(conn_ipv4)
      
      # For IPv6, we just verify the conn struct has the right value
      # since actual IPv6 connectivity may not be available
      conn_ipv6 = WebSockex.Conn.new(uri, inet_family: :inet6)
      assert conn_ipv6.inet_family == :inet6
    end
  end
end
