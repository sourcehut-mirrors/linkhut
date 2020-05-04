defmodule LinkhutWeb.ViewHelpers do
  alias LinkhutWeb.Auth.Guardian.Plug, as: GuardianPlug

  def current_user(conn), do: GuardianPlug.current_resource(conn)

  def logged_in?(conn) do
    GuardianPlug.authenticated?(conn) && GuardianPlug.current_resource(conn)
  end
end
