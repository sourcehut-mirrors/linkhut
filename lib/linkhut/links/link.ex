defmodule Linkhut.Links.Link do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: Ecto.Schema.t()

  alias Linkhut.Accounts.User
  alias Linkhut.Links.Tags

  @primary_key false
  schema "links" do
    field :id, :id, read_after_writes: true
    field :url, :string, primary_key: true
    field :user_id, :id, primary_key: true
    belongs_to :user, User, define_field: false
    field :title, :string
    field :notes, :string, default: ""
    field :notes_html, :string, default: ""
    field :tags, Tags, default: []
    field :is_private, :boolean, default: false
    field :language, :string
    field :is_unread, :boolean, default: false
    field :saves, :integer, default: 0, virtual: true
    field :score, :float, default: 0.0, virtual: true
    field :has_archive?, :boolean, virtual: true, default: false

    embeds_one :metadata, LinkMetadata, on_replace: :update do
      field :scheme, :string
      field :host, :string
      field :port, :integer
      field :path, :string
      field :query, :string
      field :fragment, :string
    end

    many_to_many :savers, User, join_through: __MODULE__, join_keys: [url: :url, user_id: :id]
    has_many :variants, __MODULE__, references: :url, foreign_key: :url

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(link, attrs, opts \\ [fetch_title: true]) do
    link
    |> cast(
      attrs,
      [:url, :user_id, :title, :notes, :tags, :is_private, :inserted_at, :is_unread],
      opts
    )
    |> validate_url()
    |> maybe_add_metadata()
    |> maybe_fetch_title(opts)
    |> validate_required([:user_id, :title, :is_private])
    |> validate_length(:title, max: 255)
    |> validate_length(:notes, max: 1024)
    |> unique_constraint(:url, name: :links_url_user_id_index, message: "has already been saved")
    |> update_unread_status()
    |> update_tags()
    |> dedupe_tags()
    |> maybe_generate_html()
  end

  defp maybe_add_metadata(changeset) do
    case get_change(changeset, :url) do
      nil ->
        changeset

      url ->
        %URI{scheme: scheme, host: host, port: port, path: path, query: query, fragment: fragment} =
          URI.parse(url)

        changeset
        |> put_embed(
          :metadata,
          %{scheme: scheme, host: host, port: port, path: path, query: query, fragment: fragment}
        )
    end
  end

  defp maybe_generate_html(changeset) do
    case get_change(changeset, :notes) do
      nil ->
        changeset

      notes ->
        force_change(
          changeset,
          :notes_html,
          HtmlSanitizeEx.Scrubber.scrub(
            Earmark.as_html!(notes, pure_links: false),
            Linkhut.Html.Scrubber
          )
        )
    end
  end

  defp update_unread_status(changeset) do
    case get_change(changeset, :is_unread) do
      nil -> changeset
      false -> force_change(changeset, :tags, remove_unread_tag(get_field(changeset, :tags, [])))
      true -> force_change(changeset, :tags, add_unread_tag(get_field(changeset, :tags, [])))
    end
  end

  defp update_tags(changeset) do
    case get_change(changeset, :tags) do
      nil ->
        changeset

      tags ->
        if Enum.any?(tags, &Tags.is_unread?/1),
          do: force_change(changeset, :is_unread, true),
          else: changeset
    end
  end

  defp dedupe_tags(changeset) do
    case get_change(changeset, :tags) do
      nil ->
        changeset

      tags ->
        force_change(
          changeset,
          :tags,
          Enum.uniq_by(
            tags,
            &if(Tags.is_unread?(&1), do: Tags.unread(), else: String.downcase(&1))
          )
        )
    end
  end

  defp add_unread_tag(tags), do: ["unread" | tags]
  defp remove_unread_tag(tags), do: Enum.reject(tags, &Tags.is_unread?/1)

  defp validate_url(changeset) do
    changeset
    |> validate_required(:url)
    |> validate_length(:url, max: 2048)
    |> validate_change(:url, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: nil} -> [{:url, "is missing a scheme"}]
        %URI{host: nil} -> [{:url, "is missing a host"}]
        _ -> []
      end
    end)
  end

  # Helpers to automagically populate the title

  defp maybe_fetch_title(changeset, opts) do
    if !Keyword.get(opts, :fetch_title, false) || !changeset.valid? ||
         get_change(changeset, :title) || !get_change(changeset, :url) do
      changeset
    else
      fetch_title(changeset)
    end
  end

  defp fetch_title(changeset) do
    url = get_change(changeset, :url)
    uri = URI.parse(url)

    with %URI{scheme: scheme, host: host} when scheme in ["http", "https"] <- uri,
         true <- Linkhut.Network.allowed_address?(host),
         {:ok, resp} <- fetch_url(url),
         ["text/html" <> _] <- Req.Response.get_header(resp, "content-type") do
      put_change(changeset, :title, Linkhut.Html.Title.title(resp.body))
    else
      _ ->
        %URI{host: host, path: path} = uri
        doc_title = Path.basename(path || "")

        if doc_title != "" do
          put_change(changeset, :title, doc_title)
        else
          put_change(changeset, :title, host)
        end
    end
  end

  defp fetch_url(url) do
    [url: url]
    |> Keyword.merge(Application.get_env(:linkhut, :req_options, []))
    |> Req.request(retry: false)
  end
end
