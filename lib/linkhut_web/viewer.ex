defmodule LinkhutWeb.Viewer do
  @moduledoc """
  Represents the viewer of the current request: the authenticated user (or an anonymous visitor)
  together with the preferences and permissions derived from them.
  """

  alias Linkhut.Accounts.Preferences.UserPreference
  alias Linkhut.Accounts.Preferences
  alias Linkhut.Accounts.User
  alias Linkhut.Archiving
  alias Linkhut.Links

  @typedoc """
  A `Viewer` struct.
  """
  @type t() :: %__MODULE__{
          user: User.t() | nil,
          preferences: UserPreference.t(),
          can_view_archives?: boolean(),
          unread_count: integer()
        }

  defstruct user: nil,
            preferences: %UserPreference{},
            can_view_archives?: false,
            unread_count: 0

  @doc "Returns viewer for an unauthenticated user"
  def anonymous, do: %__MODULE__{}

  @doc "Returns viewer for a given user"
  def for_user(%User{} = user) do
    %__MODULE__{
      user: user,
      preferences: Preferences.get_or_default(user),
      can_view_archives?: Archiving.can_view_archives?(user),
      unread_count: Links.unread_count(user.id)
    }
  end

  @doc "Whether the viewer is an authenticated user."
  def logged_in?(%__MODULE__{user: nil}), do: false
  def logged_in?(%__MODULE__{}), do: true
end
