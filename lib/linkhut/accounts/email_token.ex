defmodule Linkhut.Accounts.EmailToken do
  @moduledoc false

  @namespace "email"
  @max_age 86_400

  def new(credential, "confirm") do
    Phoenix.Token.sign(LinkhutWeb.Endpoint, @namespace, credential.email_confirmation_token)
  end

  def verify(token, "confirm") do
    Phoenix.Token.verify(LinkhutWeb.Endpoint, @namespace, token, max_age: @max_age)
  end

  def verify(_, _) do
    {:error, "unsupported"}
  end
end
