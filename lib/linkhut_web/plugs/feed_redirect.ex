defmodule LinkhutWeb.Plugs.FeedRedirect do
  @behaviour Plug

  @moduledoc """
  A simple plug that looks for the last element of the path segments and if it matches `feed.xml` then redirects the
  request to the `/feed` scope.

  Phoenix routes can only be made to match on prefixes, however it's easier for humans to append `/feed.xml` at the end
  of a URL instead of inserting `/feed` right in the middle of it.
  """

  import Phoenix.Controller, only: [redirect: 2]
  alias LinkhutWeb.Router.Helpers, as: RouteHelpers

  @doc false
  @impl true
  def init(opts \\ []), do: opts

  @doc false
  @impl true
  def call(%Plug.Conn{path_info: path_segments} = conn, _opts) do
    if redirects?(List.last(path_segments)) do
      conn
      |> redirect(to: RouteHelpers.feed_link_path(conn, :show, List.delete_at(path_segments, -1)))
    else
      conn
    end
  end

  defp redirects?("feed.xml"), do: true
  defp redirects?(segment), do: false
end
