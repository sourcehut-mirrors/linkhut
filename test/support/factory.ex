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
      title: sequence(:title, &"link-#{&1}"),
      notes: "An awesome link description",
      tags: ["test", "auto-generated"],
      is_private: false,
      language: "english",
      inserted_at: DateTime.utc_now()
    }
  end

  def snapshot_factory(attrs) do
    {user_id, attrs} =
      Map.pop_lazy(attrs, :user_id, fn -> insert(:user, credential: build(:credential)).id end)

    {link_id, attrs} = Map.pop_lazy(attrs, :link_id, fn -> insert(:link, user_id: user_id).id end)

    snapshot = %Linkhut.Archiving.Snapshot{
      user_id: user_id,
      link_id: link_id,
      type: "singlefile",
      state: :complete,
      storage_key: "local:/tmp/test/archive",
      file_size_bytes: 1024,
      processing_time_ms: 500,
      response_code: 200,
      crawler_meta: %{"tool_name" => "SingleFile", "version" => "1.0.0"}
    }

    merge_attributes(snapshot, attrs)
  end

  def archive_factory(attrs) do
    {user_id, attrs} =
      Map.pop_lazy(attrs, :user_id, fn -> insert(:user, credential: build(:credential)).id end)

    {link_id, attrs} = Map.pop_lazy(attrs, :link_id, fn -> insert(:link, user_id: user_id).id end)

    archive = %Linkhut.Archiving.Archive{
      user_id: user_id,
      link_id: link_id,
      url: sequence(:url, &"http://archive-#{&1}.example.net"),
      state: :processing,
      steps: [
        %{
          "step" => "created",
          "detail" => %{"msg" => "created"},
          "at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      ],
      total_size_bytes: 0
    }

    merge_attributes(archive, attrs)
  end
end
