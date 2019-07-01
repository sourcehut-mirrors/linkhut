defmodule Linkhut.Repo do
  use Ecto.Repo,
    otp_app: :linkhut,
    adapter: Ecto.Adapters.Postgres
end
