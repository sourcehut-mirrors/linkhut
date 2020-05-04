defmodule LinkhutWeb.Auth.Guardian do
  @moduledoc false

  use Guardian, otp_app: :linkhut
  alias Linkhut.Model.User
  alias Linkhut.Repo

  def subject_for_token(user, _claims) do
    sub = to_string(user.id)
    {:ok, sub}
  end

  def resource_from_claims(claims) do
    id = claims["sub"]

    if user = Repo.get(User, id) do
      {:ok, user}
    else
      {:error, "User not found"}
    end
  end

  def on_verify(claims, _token, _options) do
    if Repo.get(User, claims["sub"]) do
      {:ok, claims}
    else
      {:error, "User not found"}
    end
  end
end
