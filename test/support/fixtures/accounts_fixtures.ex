defmodule Linkhut.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Linkhut.Accounts` context.
  """

  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    number = System.unique_integer([:positive])

    Enum.into(attrs, %{
      username: "user#{number}",
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

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.body, "[TOKEN]")
    token
  end
end
