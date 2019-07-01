defmodule Linkhut.Web.ViewHelpers do

  alias Linkhut.Web.Auth.Guardian.Plug, as: GuardianPlug

  def current_user(conn), do: GuardianPlug.current_resource(conn)

  def logged_in?(conn), do: GuardianPlug.authenticated?(conn)

end