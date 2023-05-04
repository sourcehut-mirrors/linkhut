defmodule LinkhutWeb.Controllers.Utils do
  @moduledoc false

  use LinkhutWeb, :verified_routes

  defmodule Scope do
    @type t() :: %__MODULE__{
            user: String.t(),
            tags: [String.t()],
            url: String.t(),
            params: map()
          }
    defstruct user: nil, tags: [], url: nil, params: %{}
  end

  @doc """
  Provides the path of the current scope with the provided parameters

  ## Options

  Accepts one of the following options:
    * `:username` - reduce the scope to the given username (resets page)
    * `:tag` - reduce the scope to the given tag (resets page)
    * `:page` - provides results for the given page

  ## Examples

  Given a current path of `"/foo"`

      iex> html_path(conn)
      "/foo"
      iex> html_path(conn, username: "bob")
      "/~bob/foo"
      iex> html_path(conn, page: 3)
      "/foo?p=3"
      iex> html_path(conn, tag: "bar")
      "/foo/bar"
  """
  @spec html_path([Plug.Conn.t() | Scope.t()], Keyword.t()) :: String.t()
  def html_path(conn_or_scope, opts \\ [])

  def html_path(%Plug.Conn{} = conn, opts) do
    conn
    |> scope()
    |> html_path(opts)
  end

  def html_path(%Scope{} = scope, opts) do
    scope
    |> scope_to_map()
    |> with_overrides(opts)
    |> html_route()
  end

  @doc """
  Provides the feed path of the current scope with the provided parameters

  ## Options

  Accepts one of the following options:
    * `:username` - reduce the scope to the given username (resets page)
    * `:tag` - reduce the scope to the given tag (resets page)
    * `:page` - provides results for the given page

  ## Examples

  Given a current path of `"/foo"`

      iex> feed_path(conn)
      "/_/feed/foo"
      iex> feed_path(conn, username: "bob")
      "/_/feed/~bob/foo"
      iex> feed_path(conn, page: 3)
      "/_/feed/foo?p=3"
      iex> feed_path(conn, tag: "bar")
      "/_/feed/foo/bar"
  """
  @spec feed_path([Plug.Conn.t() | Scope.t()], Keyword.t()) :: String.t()
  def feed_path(conn_or_scope, opts \\ [])

  def feed_path(%Plug.Conn{} = conn, opts) do
    conn
    |> scope()
    |> feed_path(opts)
  end

  def feed_path(%Scope{} = scope, opts) do
    scope
    |> scope_to_map()
    |> with_overrides(opts)
    |> feed_route()
  end

  defp html_route(%{user: u, url: l, tags: t, params: p}), do: ~p"/~#{u}/-#{l}/#{t}?#{p}"
  defp html_route(%{user: u, url: l, params: p}), do: ~p"/~#{u}/-#{l}?#{p}"
  defp html_route(%{url: l, tags: t, params: p}), do: ~p"/-#{l}/#{t}?#{p}"
  defp html_route(%{url: l, params: p}), do: ~p"/-#{l}?#{p}"
  defp html_route(%{user: u, tags: t, params: p}), do: ~p"/~#{u}/#{t}?#{p}"
  defp html_route(%{user: u, params: p}), do: ~p"/~#{u}?#{p}"
  defp html_route(%{tags: t, params: p}), do: ~p"/#{t}?#{p}"
  defp html_route(%{params: p}), do: ~p"/?#{p}"

  defp feed_route(%{user: u, url: l, tags: t, params: p}), do: ~p"/_/feed/~#{u}/-#{l}/#{t}?#{p}"
  defp feed_route(%{user: u, url: l, params: p}), do: ~p"/_/feed/~#{u}/-#{l}?#{p}"
  defp feed_route(%{url: l, tags: t, params: p}), do: ~p"/_/feed/-#{l}/#{t}?#{p}"
  defp feed_route(%{url: l, params: p}), do: ~p"/_/feed/-#{l}?#{p}"
  defp feed_route(%{user: u, tags: t, params: p}), do: ~p"/_/feed/~#{u}/#{t}?#{p}"
  defp feed_route(%{user: u, params: p}), do: ~p"/_/feed/~#{u}?#{p}"
  defp feed_route(%{tags: t, params: p}), do: ~p"/_/feed/#{t}?#{p}"
  defp feed_route(%{params: p}), do: ~p"/_/feed/?#{p}"

  @spec scope(Plug.Conn.t()) :: Scope.t()
  def scope(%Plug.Conn{path_info: path, query_params: params}) do
    path = clean_path(path)

    fields =
      %{params: Map.drop(params, ["p"])}
      |> fetch_user(path)
      |> fetch_tags(path)
      |> fetch_url(path)

    struct(Scope, fields)
  end

  defp fetch_user(%{} = scope, ["~" <> user | _]), do: Map.put(scope, :user, user)
  defp fetch_user(%{} = scope, _), do: scope

  defp fetch_tags(%{} = scope, path), do: Map.put(scope, :tags, tags_from_path(path))

  defp tags_from_path(["~" <> _ | path]), do: tags_from_path(path)
  defp tags_from_path(["-" <> _ | path]), do: tags_from_path(path)
  defp tags_from_path([]), do: []
  defp tags_from_path(tags), do: tags

  defp fetch_url(%{} = scope, path), do: Map.put(scope, :url, url_from_path(path))

  defp url_from_path(["~" <> _ | path]), do: url_from_path(path)
  defp url_from_path(["-" <> url | _]), do: URI.decode(url)
  defp url_from_path(_), do: nil

  defp with_overrides(%{} = scope, user: user) do
    scope
    |> Map.put(:user, user)
    |> Map.update(:params, %{}, fn p -> Map.drop(p, ["v"]) end)
  end

  defp with_overrides(%{} = scope, url: url) do
    Map.put(scope, :url, url)
  end

  defp with_overrides(%{} = scope, tag: tag) do
    Map.update(scope, :tags, [tag], fn tags -> Enum.uniq(tags ++ [tag]) end)
  end

  defp with_overrides(%{} = scope, page: page) do
    Map.update(scope, :params, %{"p" => page}, fn p -> Map.put(p, "p", page) end)
  end

  defp with_overrides(%{} = scope, sort_by: sort_by) do
    Map.update(scope, :params, %{"sort" => sort_by}, fn p -> Map.put(p, "sort", sort_by) end)
  end

  defp with_overrides(%{} = scope, ordering: ordering) do
    Map.update(scope, :params, %{"order" => ordering}, fn p -> Map.put(p, "order", ordering) end)
  end

  defp with_overrides(%{} = scope, []), do: scope

  defp clean_path(path) do
    if List.starts_with?(path, ["_", "feed"]) or List.starts_with?(path, ["_", "unread"]) do
      Enum.drop(path, 2)
    else
      path
    end
  end

  @spec scope_to_map(Scope.t()) :: map()
  defp scope_to_map(%Scope{} = scope) do
    scope
    |> Map.from_struct()
    |> Enum.filter(fn {_, v} -> v != nil and v != [] end)
    |> Enum.into(%{})
  end
end
