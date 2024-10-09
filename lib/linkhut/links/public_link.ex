defmodule Linkhut.Links.PublicLink do
  @moduledoc false

  use Ecto.Schema
  alias Linkhut.Accounts.User

  @type t :: Ecto.Schema.t()

  @primary_key false
  schema "public_links" do
    field :id, :integer, primary_key: true
    field :inserted_at, :utc_datetime
    belongs_to :user, User, define_field: false
    field :saves, :integer
    field :rank, :float
    field :user_daily_entry, :integer
  end
end
