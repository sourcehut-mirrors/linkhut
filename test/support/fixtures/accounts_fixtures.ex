defmodule Linkhut.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Linkhut.Accounts` context.
  """

  import Ecto.Query

  alias Linkhut.Accounts

  def unique_user_email(), do: "user#{System.unique_integer([:positive])}@example.com"

  def valid_user_password(), do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    number = System.unique_integer([:positive])

    Enum.into(attrs, %{
      username: "user#{number}",
      bio: "Hi, this is my bio!",
      credential: %{
        email: "user#{number}@example.com",
        password: valid_user_password()
      }
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Linkhut.Accounts.create_user()

    user
  end

  def activate_user(%Accounts.User{id: id} = user, type \\ :active_paying) do
    {1, _} =
      Linkhut.Repo.update_all(
        from(u in Accounts.User, where: u.id == ^id),
        set: [type: type]
      )

    %{user | type: type}
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.body, "[TOKEN]")
    token
  end

  def override_token_inserted_at(token, inserted_at) when is_binary(token) do
    Linkhut.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [inserted_at: inserted_at]
    )
  end

  def override_user_inserted_at(user_id, days_old) do
    past_date = DateTime.add(DateTime.utc_now(), -days_old, :day)

    Linkhut.Repo.update_all(
      from(u in Accounts.User, where: u.id == ^user_id),
      set: [inserted_at: past_date, type: :active_free]
    )
  end
end
