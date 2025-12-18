defmodule IPv6Client do
  @moduledoc """
  Example WebSocket client that demonstrates IPv6 connection support.

  This example shows how to use the `:inet_family` option to connect
  to a WebSocket server over IPv6.

  ## Usage

      # Connect using IPv6
      {:ok, pid} = IPv6Client.start_link("ws://[::1]:8080/ws", inet_family: :inet6)

      # Connect using IPv4 (default)
      {:ok, pid} = IPv6Client.start_link("ws://127.0.0.1:8080/ws")

  """
  use WebSockex
  require Logger

  @doc """
  Start a WebSocket client connection.

  ## Options

    * `:inet_family` - Set to `:inet6` for IPv6 connections or `:inet` for IPv4 (default)
    * Other options: See `WebSockex.Conn.connection_option/0`

  """
  def start_link(url, opts \\ []) do
    WebSockex.start_link(url, __MODULE__, %{}, opts)
  end

  def handle_connect(conn, state) do
    Logger.info("Connected to #{conn.host}:#{conn.port} using #{conn.inet_family}")
    {:ok, state}
  end

  def handle_frame({type, msg}, state) do
    Logger.info("Received #{type} frame: #{inspect(msg)}")
    {:ok, state}
  end

  def handle_disconnect(%{reason: reason}, state) do
    Logger.info("Disconnected: #{inspect(reason)}")
    {:ok, state}
  end
end

# Example usage (uncomment to run):
#
# # IPv6 connection to localhost
# {:ok, pid} = IPv6Client.start_link("ws://[::1]:8080/ws", inet_family: :inet6)
#
# # IPv4 connection to localhost (default)
# {:ok, pid} = IPv6Client.start_link("ws://127.0.0.1:8080/ws")
