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
      socket_recv_timeout: 5000
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
      socket_recv_timeout: 5000
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
               socket_recv_timeout: 5000
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

      conn = WebSockex.Conn.new(uri, cacerts: WebSockex.TestServer.cacerts())

      [url: url, uri: uri, conn: conn]
    end

    test "open_socket rejects an untrusted certificate by default", context do
      conn = WebSockex.Conn.new(context.uri)

      assert {:error, %WebSockex.ConnError{original: {:tls_alert, {:unknown_ca, _}}}} =
               WebSockex.Conn.open_socket(conn)
    end

    test "open_socket with insecure false uses the default trust store path", context do
      conn = WebSockex.Conn.new(context.uri, insecure: false)

      assert {:error, %WebSockex.ConnError{original: {:tls_alert, _}}} =
               WebSockex.Conn.open_socket(conn)
    end

    test "open_socket rejects a hostname mismatch with supplied cacerts", context do
      uri = %{context.uri | host: "127.0.0.1"}
      conn = WebSockex.Conn.new(uri, cacerts: WebSockex.TestServer.cacerts())

      assert {:error, %WebSockex.ConnError{original: {:tls_alert, {:bad_certificate, _}}}} =
               WebSockex.Conn.open_socket(conn)
    end

    test "open_socket with supplied cacerts", context do
      conn =
        WebSockex.Conn.new(
          context.uri,
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
      {:ok, conn} = WebSockex.Conn.open_socket(context.conn)
      socket = conn.socket

      assert {:ok, _} = :ssl.sockname(socket)
      assert WebSockex.Conn.close_socket(conn) == %{conn | socket: nil}
      Process.sleep(50)
      assert {:error, _} = :ssl.sockname(socket)
    end

    test "open_socket through a proxy verifies the target hostname", context do
      proxy_port = start_tunnel_proxy()

      conn =
        WebSockex.Conn.new(context.uri,
          cacerts: WebSockex.TestServer.cacerts(),
          proxy: %{host: "127.0.0.1", port: proxy_port}
        )

      assert {:ok, %WebSockex.Conn{conn_mod: :ssl}} = WebSockex.Conn.open_socket(conn)

      mismatched = %{context.uri | host: "127.0.0.1"}

      bad_conn =
        WebSockex.Conn.new(mismatched,
          cacerts: WebSockex.TestServer.cacerts(),
          proxy: "http://127.0.0.1:#{proxy_port}"
        )

      assert {:error, %WebSockex.ConnError{original: {:tls_alert, {_alert, detail}}}} =
               WebSockex.Conn.open_socket(bad_conn)

      assert to_string(detail) =~ "hostname_check_failed"
    end

    test "proxy TLS failure closes the proxy socket", context do
      proxy_port = start_tunnel_proxy()
      mismatched = %{context.uri | host: "127.0.0.1"}

      bad_conn =
        WebSockex.Conn.new(mismatched,
          cacerts: WebSockex.TestServer.cacerts(),
          proxy: %{host: "127.0.0.1", port: proxy_port}
        )

      ports_before = owned_port_count()

      assert {:error, %WebSockex.ConnError{original: {:tls_alert, _}}} =
               WebSockex.Conn.open_socket(bad_conn)

      assert owned_port_count() == ports_before
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
      conn = WebSockex.Conn.new(uri, cacerts: WebSockex.TestServer.cacerts())
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

  test "parses proxy credentials from a URL" do
    conn = WebSockex.Conn.new("wss://example.com/ws", proxy: "http://user:p%40ss@proxy.test:8080")

    assert conn.proxy == %{
             host: "proxy.test",
             port: 8080,
             username: "user",
             password: "p@ss"
           }
  end

  test "ws connections are tunneled through the configured proxy" do
    parent = self()
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: 0, ip: {127, 0, 0, 1}])
    {:ok, proxy_port} = :inet.port(listen)

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      {:ok, request} = recv_headers(socket)
      send(parent, {:proxy_request, request})
      :gen_tcp.send(socket, "HTTP/1.1 200 Connection Established\r\n\r\n")
    end)

    conn =
      WebSockex.Conn.new("ws://127.0.0.1:9/ws",
        proxy: %{host: "127.0.0.1", port: proxy_port, username: "user", password: "secret"}
      )

    assert {:ok, %{socket: socket}} = WebSockex.Conn.open_socket(conn)
    assert is_port(socket)

    assert_receive {:proxy_request, request}
    assert request =~ "CONNECT 127.0.0.1:9 HTTP/1.1"
    assert request =~ "Proxy-Authorization: Basic #{Base.encode64("user:secret")}"
  end

  test "ws connections do not dial the target when a proxy is configured", context do
    conn = WebSockex.Conn.new(context.uri, proxy: %{host: "127.0.0.1", port: 1})

    assert {:error, %WebSockex.ConnError{original: :econnrefused}} =
             WebSockex.Conn.open_socket(conn)
  end

  test "proxy connects honor socket_options" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: 0, ip: {127, 0, 0, 1}])
    {:ok, proxy_port} = :inet.port(listen)

    conn =
      WebSockex.Conn.new("ws://127.0.0.1:9/ws",
        proxy: %{host: "127.0.0.1", port: proxy_port},
        socket_options: [ip: {192, 0, 2, 1}]
      )

    assert {:error, %WebSockex.ConnError{original: :eaddrnotavail}} =
             WebSockex.Conn.open_socket(conn)

    :gen_tcp.close(listen)
  end

  test "failed proxy tunnels close the proxy socket" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: 0, ip: {127, 0, 0, 1}])
    {:ok, proxy_port} = :inet.port(listen)
    spawn_link(fn -> reject_proxy_connections(listen) end)

    conn =
      WebSockex.Conn.new("ws://127.0.0.1:9/ws",
        proxy: %{host: "127.0.0.1", port: proxy_port}
      )

    ports_before = owned_port_count()

    for _ <- 1..3 do
      assert {:error, %WebSockex.ConnError{original: {:proxy_error, 407, _}}} =
               WebSockex.Conn.open_socket(conn)
    end

    assert owned_port_count() == ports_before
    :gen_tcp.close(listen)
  end

  test "proxy recv timeouts close the proxy socket" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: 0, ip: {127, 0, 0, 1}])
    {:ok, proxy_port} = :inet.port(listen)
    spawn_link(fn -> accept_and_hold(listen) end)

    conn =
      WebSockex.Conn.new("ws://127.0.0.1:9/ws",
        proxy: %{host: "127.0.0.1", port: proxy_port},
        socket_recv_timeout: 50
      )

    ports_before = owned_port_count()

    for _ <- 1..2 do
      assert {:error, %WebSockex.ConnError{original: :timeout}} = WebSockex.Conn.open_socket(conn)
    end

    assert owned_port_count() == ports_before
    :gen_tcp.close(listen)
  end

  test "CONNECT request brackets IPv6 targets" do
    parent = self()
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: 0, ip: {127, 0, 0, 1}])
    {:ok, proxy_port} = :inet.port(listen)

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      {:ok, request} = recv_headers(socket)
      send(parent, {:proxy_request, request})
      :gen_tcp.send(socket, "HTTP/1.1 200 Connection Established\r\n\r\n")
    end)

    conn = WebSockex.Conn.new("ws://[::1]:9/ws", proxy: %{host: "127.0.0.1", port: proxy_port})

    assert {:ok, %{socket: socket}} = WebSockex.Conn.open_socket(conn)
    assert is_port(socket)

    assert_receive {:proxy_request, request}
    assert request =~ "CONNECT [::1]:9 HTTP/1.1"
    assert request =~ "Host: [::1]:9"
    refute request =~ "CONNECT ::1:9"

    :gen_tcp.close(socket)
    :gen_tcp.close(listen)
  end

  test "invalid proxy configuration is an error" do
    url = "ws://127.0.0.1:9/ws"
    string_keys = %{"host" => "127.0.0.1", "port" => 8080}

    assert {:error, %WebSockex.ConnError{original: {:invalid_proxy, "proxy.corp.com:8080"}}} =
             WebSockex.Conn.new(url, proxy: "proxy.corp.com:8080")

    assert {:error, %WebSockex.ConnError{original: {:invalid_proxy, ^string_keys}}} =
             WebSockex.Conn.new(url, proxy: string_keys)

    assert {:error, %WebSockex.ConnError{original: {:invalid_proxy, %{host: "127.0.0.1"}}}} =
             WebSockex.Conn.new(url, proxy: %{host: "127.0.0.1"})

    assert {:error, %WebSockex.ConnError{original: {:invalid_proxy, :bad}}} =
             WebSockex.Conn.new(url, proxy: :bad)
  end

  test "open_socket rejects an unusable proxy instead of dialing the target", context do
    proxy = %{"host" => "127.0.0.1", "port" => context.uri.port}
    conn = %{context.conn | proxy: proxy}
    ports_before = owned_port_count()

    assert {:error, %WebSockex.ConnError{original: {:invalid_proxy, ^proxy}}} =
             WebSockex.Conn.open_socket(conn)

    assert owned_port_count() == ports_before
  end

  test "controlling_process", %{conn: conn} do
    socket = conn.socket
    # Start a random process
    {:ok, agent_pid} = Agent.start_link(fn -> :test end)

    assert :erlang.port_info(socket, :connected) == {:connected, self()}

    WebSockex.Conn.controlling_process(conn, agent_pid)

    assert :erlang.port_info(socket, :connected) == {:connected, agent_pid}
  end

  defp owned_port_count do
    me = self()

    Enum.count(:erlang.ports(), fn port ->
      case :erlang.port_info(port, :connected) do
        {:connected, ^me} -> true
        _ -> false
      end
    end)
  end

  defp reject_proxy_connections(listen) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        spawn_link(fn -> reject_proxy_connections(listen) end)

        case recv_headers(socket) do
          {:ok, _} ->
            :gen_tcp.send(socket, "HTTP/1.1 407 Proxy Authentication Required\r\n\r\n")

          {:error, _} ->
            :ok
        end

        Process.sleep(:infinity)

      {:error, :closed} ->
        :ok
    end
  end

  defp accept_and_hold(listen) do
    case :gen_tcp.accept(listen) do
      {:ok, _socket} ->
        spawn_link(fn -> accept_and_hold(listen) end)
        Process.sleep(:infinity)

      {:error, :closed} ->
        :ok
    end
  end

  defp start_tunnel_proxy do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: 0, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listen)
    spawn_link(fn -> accept_tunnel(listen) end)
    port
  end

  defp accept_tunnel(listen) do
    case :gen_tcp.accept(listen) do
      {:ok, client} ->
        spawn_link(fn -> accept_tunnel(listen) end)
        tunnel_client(client)

      {:error, :closed} ->
        :ok
    end
  end

  defp tunnel_client(client) do
    {:ok, request} = recv_headers(client)
    [host, port] = request |> tunnel_target() |> String.split(":")

    {:ok, upstream} =
      :gen_tcp.connect(String.to_charlist(host), String.to_integer(port), [
        :binary,
        active: false,
        packet: 0
      ])

    :ok = :gen_tcp.send(client, "HTTP/1.1 200 Connection Established\r\n\r\n")
    :inet.setopts(client, active: :once)
    :inet.setopts(upstream, active: :once)
    relay(client, upstream)
  end

  defp tunnel_target(request) do
    ["CONNECT", target | _] = String.split(request, [" ", "\r\n"], trim: true)
    target
  end

  defp recv_headers(socket, buffer \\ "") do
    if String.contains?(buffer, "\r\n\r\n") do
      {:ok, buffer}
    else
      case :gen_tcp.recv(socket, 0, 2_000) do
        {:ok, data} -> recv_headers(socket, buffer <> data)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp relay(client, upstream) do
    receive do
      {:tcp, ^client, data} ->
        :gen_tcp.send(upstream, data)
        :inet.setopts(client, active: :once)
        relay(client, upstream)

      {:tcp, ^upstream, data} ->
        :gen_tcp.send(client, data)
        :inet.setopts(upstream, active: :once)
        relay(client, upstream)

      {:tcp_closed, socket} ->
        other = if socket == client, do: upstream, else: client
        :gen_tcp.close(other)

      {:tcp_error, _socket, _reason} ->
        :gen_tcp.close(client)
        :gen_tcp.close(upstream)
    end
  end
end
