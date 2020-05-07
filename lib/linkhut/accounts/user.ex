defmodule Linkhut.Accounts.User do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset
  alias Linkhut.Accounts.Credential

  @username_format ~r/^[a-zA-Z\d]{3,}$/

  schema "users" do
    field :username, :string
    field :bio, :string
    has_one :credential, Credential

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :bio])
    |> validate_required([:username])
    |> unique_constraint(:username)
    |> validate_format(:username, @username_format)
  end
end
