defmodule Linkhut.Web.Plugs.AuthenticationPlug do
  @moduledoc """
  Pipeline which ensures a user is authenticated
  """

  use Guardian.Plug.Pipeline,
    otp_app: :linkhut,
    error_handler: Linkhut.Web.Auth.SessionController,
    module: Linkhut.Web.Auth.Guardian

  # If there is a session token, validate it
  plug(Guardian.Plug.VerifySession, claims: %{"typ" => "access"})

  # If there is an authorization header, validate it
  plug(Guardian.Plug.VerifyHeader, claims: %{"typ" => "access"})

  # Load the user if either of the verifications worked
  plug(Guardian.Plug.LoadResource, allow_blank: true)
end
