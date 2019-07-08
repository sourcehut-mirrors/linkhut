defmodule Linkhut.Web.LinkController do
  use Linkhut.Web, :controller

  def index(conn, _) do
    conn
    |> render("index.html")
  end

  def show(conn, %{"username" => username}) do
    cond do
      String.match?(username, ~r/[A-Za-z]+/) ->
        conn
        |> render("show.html", username: String.downcase(username))

      true ->
        conn
        |> put_flash(:error, "Wrong username")
        |> render("show.html", username: "")
    end
  end
end
