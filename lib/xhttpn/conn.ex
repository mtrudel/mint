defmodule XHTTPN.Conn do
  @moduledoc """
  Single interface for `XHTTP1.Conn` and `XHTTP2.Conn` with version negotiation support.
  """

  import XHTTP.Util

  @behaviour XHTTP.ConnBehaviour

  @default_protocols [:http1, :http2]

  def connect(scheme, hostname, port, opts \\ []) do
    {protocols, opts} = Keyword.pop(opts, :protocols, @default_protocols)

    case Enum.sort(protocols) do
      [:http1] -> XHTTP1.Conn.connect(scheme, hostname, port, opts)
      [:http2] -> XHTTP2.Conn.connect(scheme, hostname, port, opts)
      [:http1, :http2] -> negotiate(scheme, hostname, port, opts)
    end
  end

  # This function knows about XHTTP1.Conn / XHTTP2.Conn internals
  def transport_opts() do
    [
      packet: :raw,
      mode: :binary,
      active: false,
      alpn_advertised_protocols: ["http/1.1", "h2"]
    ]
  end

  def initiate(transport, transport_state, hostname, port, opts),
    do: alpn_negotiate(transport, transport_state, hostname, port, opts)

  def open?(conn), do: conn_module(conn).open?(conn)

  def request(conn, method, path, headers, body \\ nil),
    do: conn_module(conn).request(conn, method, path, headers, body)

  def stream_request_body(conn, ref, body),
    do: conn_module(conn).stream_request_body(conn, ref, body)

  def stream(conn, message), do: conn_module(conn).stream(conn, message)

  def put_private(conn, key, value), do: conn_module(conn).put_private(conn, key, value)

  def get_private(conn, key, default \\ nil),
    do: conn_module(conn).get_private(conn, key, default)

  def delete_private(conn, key), do: conn_module(conn).delete_private(conn, key)

  defp negotiate(scheme, hostname, port, opts) do
    transport = scheme_to_transport(scheme)

    transport_opts =
      opts
      |> Keyword.get(:transport_opts, [])
      |> Keyword.merge(transport_opts())

    with {:ok, socket} <- transport.connect(hostname, port, transport_opts) do
      case transport do
        XHTTP.Transport.TCP -> http1_with_upgrade(transport, socket, hostname, port, opts)
        XHTTP.Transport.SSL -> alpn_negotiate(transport, socket, hostname, port, opts)
      end
    end
  end

  defp http1_with_upgrade(_transport, _socket, _hostname, _port, _opts) do
    # TODO
    # NOTE: Since this can be unreliable it should be an option to do upgrade from HTTP1
    raise "not implemented yet"
  end

  defp alpn_negotiate(transport, socket, hostname, port, opts) do
    case transport.negotiated_protocol(socket) do
      {:ok, "http/1.1"} ->
        XHTTP1.Conn.initiate(transport, socket, hostname, port, opts)

      {:ok, "h2"} ->
        XHTTP2.Conn.initiate(transport, socket, hostname, port, opts)

      {:error, :protocol_not_negotiated} ->
        # Assume HTTP1 if ALPN is not supported
        {:ok, XHTTP1.Conn.initiate(transport, socket, hostname, port, opts)}

      {:ok, protocol} ->
        {:error, {:bad_alpn_protocol, protocol}}
    end
  end

  defp conn_module(%XHTTP1.Conn{}), do: XHTTP1.Conn
  defp conn_module(%XHTTP2.Conn{}), do: XHTTP2.Conn
end
