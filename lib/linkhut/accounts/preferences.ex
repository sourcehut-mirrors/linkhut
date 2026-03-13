defmodule Linkhut.Accounts.Preferences do
  @moduledoc "Manages per-user preferences (display, defaults, privacy)."

  import Ecto.Query
  alias Linkhut.Accounts.Preferences.UserPreference
  alias Linkhut.Accounts.User
  alias Linkhut.Repo

  @iana_regions ~w(Africa America Antarctica Asia Atlantic Australia Europe Indian Pacific)

  @doc """
  Returns the list of valid timezone options as `{label, value}` tuples.

  Filters Tzdata's canonical zones to standard IANA geographic regions,
  excluding legacy aliases and offset-based zones. Used for both
  validation and the settings dropdown.
  """
  @spec timezone_options() :: [{String.t(), String.t()}]
  def timezone_options do
    Tzdata.canonical_zone_list()
    |> Enum.filter(fn tz ->
      case String.split(tz, "/", parts: 2) do
        [region, _] -> region in @iana_regions
        _ -> false
      end
    end)
    |> Enum.sort()
    |> Enum.map(&{&1, &1})
  end

  @doc """
  Returns the list of valid timezone names.
  """
  @spec valid_timezones() :: [String.t()]
  def valid_timezones do
    Enum.map(timezone_options(), fn {_label, value} -> value end)
  end

  @doc """
  Returns the user's preferences, or a struct with defaults if none exist.

  Never returns nil — callers can always access fields without nil-checking.
  """
  @spec get_or_default(User.t()) :: UserPreference.t()
  def get_or_default(%User{id: user_id}) do
    fetch_or_build(user_id)
  end

  @doc """
  Inserts or updates preferences for the given user.

  Creates the row on first save (upsert).
  """
  @spec upsert(User.t(), map()) :: {:ok, UserPreference.t()} | {:error, Ecto.Changeset.t()}
  def upsert(%User{id: user_id}, attrs) do
    user_id
    |> fetch_or_build()
    |> UserPreference.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Returns a changeset for form rendering.
  """
  @spec change(UserPreference.t(), map()) :: Ecto.Changeset.t()
  def change(%UserPreference{} = preference, attrs \\ %{}) do
    UserPreference.changeset(preference, attrs)
  end

  defp fetch_or_build(user_id) do
    Repo.one(from p in UserPreference, where: p.user_id == ^user_id) ||
      %UserPreference{user_id: user_id}
  end
end
