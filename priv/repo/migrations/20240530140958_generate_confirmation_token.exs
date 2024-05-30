defmodule Linkhut.Repo.Migrations.GenerateConfirmationToken do
  use Ecto.Migration
  import Ecto.Query
  import Ecto.Changeset

  def change do
    if direction() == :up do
      execute(&execute_up/0)
    end
  end

  defp execute_up() do
    query =
      from(l in Linkhut.Accounts.Credential,
        where: is_nil(l.email_confirmation_token)
      )

    stream = Linkhut.Repo.stream(query)

    Linkhut.Repo.transaction(fn ->
      stream
      |> Enum.map(fn credential ->
        credential
        |> cast(%{}, [])
        |> Linkhut.Accounts.Credential.put_email_confirmation_token()
      end)
      |> Enum.with_index()
      |> Enum.reduce(Ecto.Multi.new(), fn {changeset, idx}, multi ->
        Ecto.Multi.update(multi, {:update, idx}, changeset)
      end)
      |> Linkhut.Repo.transaction()
    end)
  end
end
