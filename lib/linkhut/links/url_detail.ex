defmodule Linkhut.Links.UrlDetail do
  @moduledoc """
  Aggregate metadata about a URL's public bookmarks across all users.
  """

  alias Linkhut.Links.Link

  @type save_info :: %{username: String.t(), saved_at: DateTime.t()}
  @type tag_info :: %{tag: String.t(), count: non_neg_integer()}
  @type activity_bucket :: %{period: DateTime.t(), count: non_neg_integer()}

  @type t :: %__MODULE__{
          url: String.t(),
          title: String.t() | nil,
          total_saves: non_neg_integer(),
          first_save: save_info() | nil,
          latest_save: save_info() | nil,
          current_user_bookmark: Link.t() | nil,
          common_tags: [tag_info()],
          domain_saves: non_neg_integer(),
          activity: %{granularity: :hour | :day | :week | :month, buckets: [activity_bucket()]}
        }

  @enforce_keys [:url, :title, :total_saves, :first_save, :latest_save]
  defstruct [
    :url,
    :title,
    :total_saves,
    :first_save,
    :latest_save,
    :current_user_bookmark,
    common_tags: [],
    domain_saves: 0,
    activity: %{granularity: :week, buckets: []}
  ]
end
