defmodule LinkhutWeb.Api.PostsController do
  use LinkhutWeb, :controller

  plug ExOauth2Provider.Plug.EnsureScopes,
       [scopes: ~w(posts:write)] when action in [:add, :delete]

  plug ExOauth2Provider.Plug.EnsureScopes,
       [scopes: ~w(posts:read)] when action in [:update, :get, :recent, :dates, :all, :suggest]

  alias Linkhut.Links
  alias Linkhut.Links.Link
  alias Linkhut.Tags

  def update(conn, _) do
    user = conn.assigns[:current_user]

    conn
    |> render(:update, %{last_update: last_update(user)})
  end

  def add(conn, %{"url" => url, "description" => title, "replace" => "yes"} = params) do
    user = conn.assigns[:current_user]

    link_params =
      Enum.into(
        ~w(notes tags is_private is_unread),
        %{"title" => title},
        &{&1, value(&1, params)}
      )

    with %Link{} = link <- Links.get(url, user.id),
         {:ok, _} <- Links.update_link(link, link_params) do
      render(conn, :done)
    else
      _ -> render(conn, :error)
    end
  end

  def add(conn, %{"url" => url, "description" => title} = params) do
    user = conn.assigns[:current_user]

    link_params =
      Enum.into(
        ~w(notes tags is_private is_unread inserted_at),
        %{"url" => url, "title" => title},
        &{&1, value(&1, params)}
      )

    case Links.create_link(user, link_params) do
      {:ok, _} -> render(conn, :done)
      {:error, _} -> render(conn, :error)
    end
  end

  def delete(conn, %{"url" => url}) do
    user = conn.assigns[:current_user]

    with %Link{} = link <- Links.get(url, user.id),
         {:ok, _} <- Links.delete_link(link) do
      render(conn, :done)
    else
      _ -> render(conn, :error)
    end
  end

  def get(conn, %{"url" => url} = params) do
    user = conn.assigns[:current_user]

    case Links.get(url, user.id) do
      %Link{} = link ->
        conn
        |> render(:get,
          date: DateTime.to_date(link.inserted_at),
          links: [link],
          meta: value("meta", params),
          tag: Map.get(params, "tag", "")
        )

      _ ->
        render(conn, :error)
    end
  end

  def get(conn, %{"hashes" => hashes} = params) do
    user = conn.assigns[:current_user]

    conn
    |> render(:get,
      links: Links.all(user, hashes: String.split(hashes, " ", trim: true)),
      meta: value("meta", params),
      tag: ""
    )
  end

  def get(conn, %{"dt" => date} = params) do
    user = conn.assigns[:current_user]
    date = Date.from_iso8601!(date)
    links = Links.all(user, dt: date, tags: value("tag", params))

    conn
    |> render(:get,
      date: date,
      links: links,
      meta: value("meta", params),
      tag: Map.get(params, "tag", "")
    )
  end

  def get(conn, params) when map_size(params) == 0 do
    user = conn.assigns[:current_user]

    get(conn, Map.put(params, "dt", last_update(user) |> DateTime.to_date() |> Date.to_iso8601()))
  end

  def get(conn, %{} = params) do
    user = conn.assigns[:current_user]
    links = Links.all(user, tags: value("tag", params))

    conn
    |> render(:get,
      links: links,
      meta: value("meta", params),
      tag: Map.get(params, "tag", "")
    )
  end

  def recent(conn, params) do
    user = conn.assigns[:current_user]
    tags = value("tag", params)
    count = value("count", params)

    conn
    |> render(:recent,
      date: last_update(user),
      links: Links.all(user, tags: tags, count: count),
      tag: Map.get(params, "tag", "")
    )
  end

  def dates(conn, params) do
    user = conn.assigns[:current_user]
    tags = value("tag", params)

    dates =
      Links.all(user, tags: tags)
      |> Enum.frequencies_by(fn %{inserted_at: dt} -> DateTime.to_date(dt) end)
      |> Enum.sort_by(fn {date, _} -> date end, {:desc, Date})

    conn
    |> render(:dates,
      date: last_update(user),
      dates: dates,
      tag: Map.get(params, "tag", "")
    )
  end

  def all(conn, %{"hashes" => _}) do
    user = conn.assigns[:current_user]

    conn
    |> render(:all_hashes, links: Links.all(user))
  end

  def all(conn, params) do
    user = conn.assigns[:current_user]
    tags = value("tag", params)
    start = value("start", params)
    results = value("results", params)
    from = value("fromdt", params)
    to = value("todt", params)

    filters = [tags: tags, start: start, count: results, from: from, to: to]

    conn
    |> render(:all,
      links: Links.all(user, filters),
      tag: Map.get(params, "tag", ""),
      meta: value("meta", params)
    )
  end

  def suggest(conn, %{"url" => url}) do
    user = conn.assigns[:current_user]

    popular =
      Links.all(url: url, is_private: false)
      |> Tags.for_links()
      |> Enum.map(fn %{tag: tag} -> tag end)

    recommended =
      Tags.all(user, tags: popular)
      |> Enum.map(fn %{tag: tag} -> tag end)

    popular = popular -- recommended

    conn
    |> render(:suggest, popular: popular, recommended: recommended)
  end

  defp last_update(user) do
    case link = Links.most_recent(user) do
      %Link{} -> max(link.inserted_at, link.updated_at)
      nil -> DateTime.from_unix!(0)
    end
  end

  defp value("notes", params), do: Map.get(params, "extended", "")

  defp value("tags", params), do: Map.get(params, "tags", "")

  defp value("is_private", params) do
    case Map.get(params, "shared") do
      "no" -> true
      _ -> false
    end
  end

  defp value("is_unread", params) do
    case Map.get(params, "toread") do
      "yes" -> true
      _ -> false
    end
  end

  defp value("inserted_at", params) do
    with dt <- Map.get(params, "dt", ""),
         {:ok, datetime, _} <- DateTime.from_iso8601(dt),
         look_ahead when look_ahead < 600 <- DateTime.diff(datetime, DateTime.utc_now(:second)) do
      datetime
    else
      _ -> DateTime.utc_now()
    end
  end

  defp value("meta", %{"meta" => "yes"}), do: true
  defp value("meta", _params), do: false

  defp value("tag", params), do: String.split(Map.get(params, "tag", ""), ~r{[, ]}, trim: true)

  defp value("count", %{"count" => count}) when is_binary(count) do
    case Integer.parse(count) do
      {count, ""} -> value("count", %{"count" => count})
      _ -> 15
    end
  end

  defp value("count", %{"count" => count}) when count >= 1 and count <= 100, do: count
  defp value("count", _), do: 15

  defp value("start", %{"start" => start}) when is_binary(start) do
    case Integer.parse(start) do
      {start, ""} -> value("start", %{"start" => start})
      _ -> 0
    end
  end

  defp value("start", %{"start" => start}) when start >= 1, do: start
  defp value("start", _), do: 0

  defp value("results", %{"results" => results}) when is_binary(results) do
    case Integer.parse(results) do
      {results, ""} -> value("results", %{"results" => results})
      _ -> 1000
    end
  end

  defp value("results", %{"results" => results}) when results >= 1 and results <= 100_000,
    do: results

  defp value("results", _), do: 1000

  defp value("fromdt", params) do
    with dt <- Map.get(params, "fromdt", ""),
         {:ok, datetime, _} <- DateTime.from_iso8601(dt) do
      datetime
    else
      _ -> nil
    end
  end

  defp value("todt", params) do
    with dt <- Map.get(params, "todt", ""),
         {:ok, datetime, _} <- DateTime.from_iso8601(dt) do
      datetime
    else
      _ -> nil
    end
  end
end
