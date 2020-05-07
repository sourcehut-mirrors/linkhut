defmodule Linkhut.Factory do
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

  def link_factory do
    %Linkhut.Model.Link{
      user_id: build(:user).id,
      url: sequence(:url, &"http://link-#{&1}.example.net"),
      title: sequence(:title, &"link-#{&1}"),
      notes: "An awesome link description",
      tags: ["test", "auto-generated"],
      is_private: false,
      language: "english"
    }
  end
end
