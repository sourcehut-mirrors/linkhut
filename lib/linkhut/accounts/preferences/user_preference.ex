defmodule Linkhut.Accounts.Preferences.UserPreference do
  @moduledoc "Schema for per-user display and behavior preferences."

  use Ecto.Schema
  import Ecto.Changeset
  alias Linkhut.Accounts.User

  @type t :: Ecto.Schema.t()

  schema "user_preferences" do
    belongs_to :user, User
    field :timezone, :string
    field :show_url, :boolean, default: true
    field :show_exact_dates, :boolean, default: false
    field :default_private, :boolean, default: false
    field :strip_tracking_params, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @cast_fields [:timezone, :show_url, :show_exact_dates, :default_private, :strip_tracking_params]

  @doc false
  def changeset(preference, attrs) do
    preference
    |> cast(attrs, @cast_fields)
    |> validate_inclusion(:timezone, Linkhut.Accounts.Preferences.valid_timezones(),
      message: "is not a valid timezone"
    )
    |> unique_constraint(:user_id)
  end
end
