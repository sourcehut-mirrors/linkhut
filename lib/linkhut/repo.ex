defmodule Linkhut.Repo do
  use Ecto.Repo,
    otp_app: :linkhut,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query
  alias Linkhut.Repo
  alias Linkhut.Model.{User, Link, Tags}

  def links(user, attrs \\ []) do
    query = from(l in Link, where: l.user_id == ^user.id)
    Repo.all(query)
  end
end
