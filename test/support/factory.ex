defmodule Linkhut.Factory do
  use ExMachina.Ecto, repo: Linkhut.Repo

  def user_factory do
    %Linkhut.Model.User{
      username: "neo",
      email: sequence(:email, &"email-#{&1}@example.net"),
      password: "follow the white rabbit",
      bio: "I know Kung Fu"
    }
  end
end
