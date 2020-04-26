defmodule Linkhut.Repo do
  use Ecto.Repo,
    otp_app: :linkhut,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query
  alias Linkhut.Model.{Link, Tags, User}
  alias Linkhut.Repo

  def links(user, attrs \\ [])

  def links(username, attrs) when is_binary(username) do
    user = Repo.get_by(User, username: username)

    if user do
      links(user)
    else
      []
    end
  end

  def links(user, attrs) do
    query = from(l in Link, where: l.user_id == ^user.id)

    Repo.all(query)
    |> Repo.preload(:user)
  end

  def links_by_date(user, attrs \\ []) do
    Enum.group_by(links(user, attrs), fn link -> DateTime.to_date(link.inserted_at) end)
  end

  def link(url, user_id) do
    Repo.get_by(Link, url: url, user_id: user_id)
  end
end
