defmodule Linkhut.Web.FeedController do
  use Linkhut.Web, :controller

  alias Linkhut.Model.Link
  alias Linkhut.Model.User
  alias Linkhut.Repo

  def feed(conn, %{"username" => username}) do
    links = Repo.links(username)

    conn
    |> render("feed.xml", username: username, url: current_url(conn), links: links)
  end
end
