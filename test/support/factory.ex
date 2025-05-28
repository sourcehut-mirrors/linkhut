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
      username: sequence("username-"),
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
end
