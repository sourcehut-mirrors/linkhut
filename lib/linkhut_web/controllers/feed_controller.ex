defmodule LinkhutWeb.FeedController do
  use LinkhutWeb, :controller

  alias Linkhut.Links

  def show(conn, %{"username" => username}) do
    links = Links.get_links(username)

    conn
    |> render("feed.xml", username: username, url: current_url(conn), links: links)
  end
end
