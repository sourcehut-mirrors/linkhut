defmodule Linkhut.Web.ViewHelpers do

  def current_user(conn), do: Linkhut.Web.Auth.Guardian.Plug.current_resource(conn)

  def logged_in?(conn), do: Linkhut.Web.Auth.Guardian.Plug.authenticated?(conn)

end