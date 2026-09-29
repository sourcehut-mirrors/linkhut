defmodule Linkhut.Factory do
  @moduledoc """
  This module defines factories for creating test data to use in tests.
  """

  use ExMachina.Ecto, repo: Linkhut.Repo

  def credential_factory do
    %Linkhut.Accounts.Credential{
      email: sequence(:email, &"email-#{&1}@example.net"),
      password: sequence("password-")
    }
  end

  def user_factory do
    %Linkhut.Accounts.User{
      username: sequence("username"),
      credential: build(:credential),
      bio: "An awesome biography"
    }
  end

  def access_token_factory do
    %Linkhut.Oauth.AccessToken{
      token: sequence("token-"),
      scopes: &"#{&1}",
      resource_owner_id: build(:user).id
    }
  end

  def link_factory do
    %Linkhut.Links.Link{
      user_id: build(:user).id,
      url: sequence(:url, &"http://link-#{&1}.example.net"),
      normalized_url: fn link -> Linkhut.Links.Url.normalize(link.url) end,
      metadata: &struct(Linkhut.Links.Link.LinkMetadata, Map.from_struct(URI.parse(&1.url))),
      title: sequence(:title, &"link-#{&1}"),
      notes: "An awesome link description",
      tags: ["test", "auto-generated"],
      is_private: false,
      language: "english",
      inserted_at: DateTime.utc_now()
    }
  end

  def subscription_factory do
    %Linkhut.Subscriptions.Subscription{
      plan: :supporter,
      status: :active
    }
  end

  def snapshot_factory(attrs) do
    {user_id, attrs} =
      Map.pop_lazy(attrs, :user_id, fn -> insert(:user, credential: build(:credential)).id end)

    {link_id, attrs} = Map.pop_lazy(attrs, :link_id, fn -> insert(:link, user_id: user_id).id end)

    snapshot = %Linkhut.Archiving.Snapshot{
      user_id: user_id,
      link_id: link_id,
      format: "webpage",
      source: "singlefile",
      state: :complete,
      storage_key: Linkhut.Archiving.StorageKey.local("/tmp/test/archive"),
      file_size_bytes: 1024,
      processing_time_ms: 500,
      response_code: 200,
      crawler_meta: %{"tool_name" => "SingleFile", "tool_version" => "1.0.0", "version" => "1"}
    }

    merge_attributes(snapshot, attrs)
  end

  def create_snapshot(link_id, user_id, attrs \\ %{}) do
    %Linkhut.Archiving.Snapshot{link_id: link_id, user_id: user_id}
    |> Linkhut.Archiving.Snapshot.create_changeset(attrs)
    |> Linkhut.Repo.insert()
  end

  def crawl_run_factory do
    %Linkhut.Archiving.CrawlRun{link_id: fn -> insert(:link, user_id: insert(:user).id).id end}
  end

  def link_archival_factory do
    %Linkhut.Archiving.LinkArchival{version: "1"}
  end
end
