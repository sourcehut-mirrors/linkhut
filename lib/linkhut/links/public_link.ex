defmodule Linkhut.Links.PublicLink do
  @moduledoc false

  use Ecto.Schema
  alias Linkhut.Accounts.User

  @type t :: Ecto.Schema.t()

  @primary_key false
  schema "public_links" do
    field :url, :string, primary_key: true
    field :user_id, :id, primary_key: true
    belongs_to :user, User, define_field: false
    field :saves, :integer
    field :first, :utc_datetime
    field :last, :utc_datetime
  end
end
