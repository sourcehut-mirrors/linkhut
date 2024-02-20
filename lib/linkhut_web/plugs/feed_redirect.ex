defmodule LinkhutWeb.Plugs.FeedRedirect do
  @behaviour Plug

  @moduledoc """
  A simple plug that looks for the last element of the path segments and if it matches `feed.xml` then redirects the
  request to the `/_/feed` scope.

  Phoenix routes can only be made to match on prefixes, however it's easier for humans to append `/feed.xml` at the end
  of a URL instead of inserting `/_/feed` right in the middle of it.
  """

  import Phoenix.Controller, only: [redirect: 2]
  alias LinkhutWeb.Controllers.Utils

  @doc false
  @impl true
  def init(opts \\ []), do: opts

  @doc false
  @impl true
  def call(%Plug.Conn{path_info: path_segments} = conn, opts) do
    call(conn, List.last(path_segments), opts)
  end

  defp call(%Plug.Conn{path_info: path_segments} = conn, "feed.xml", _) do
    conn
    |> redirect(
      to: Utils.feed_path(%Plug.Conn{conn | path_info: List.delete_at(path_segments, -1)})
    )
  end

  defp call(conn, _, _), do: conn
end
