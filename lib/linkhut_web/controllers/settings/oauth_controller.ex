defmodule LinkhutWeb.Settings.OauthController do
  use LinkhutWeb, :controller

  alias Linkhut.Oauth
  alias Linkhut.Oauth.Application

  @moduledoc """
  Controller for OAuth management
  """
  plug :put_view, LinkhutWeb.SettingsView

  def show(conn, _) do
    user = conn.assigns[:current_user]

    render(conn, "oauth/index.html",
      personal_access_tokens: Oauth.get_tokens(user),
      authorized_applications: Oauth.get_authorized_applications_for(user),
      applications: Oauth.get_applications_for(user)
    )
  end

  def new_personal_token(conn, _) do
    render(conn, "oauth/personal_token/new.html")
  end

  def create_personal_token(conn, %{"comment" => comment}) do
    user = conn.assigns[:current_user]

    token = Oauth.create_token!(user, %{comment: String.trim(comment)})
    render(conn, "oauth/personal_token/show.html", token: token.token)
  end

  def revoke_token(conn, %{"id" => token_id, "access_token" => %{"id" => id}})
      when token_id == id do
    user = conn.assigns[:current_user]

    token =
      Oauth.get_token!(user, token_id)
      |> Oauth.revoke!()

    conn
    |> put_flash(:info, "Revoked token: #{String.slice(token.token, 0, 8)}...")
    |> redirect(to: Routes.oauth_path(conn, :show))
  end

  def revoke_token(conn, %{"id" => token_id}) do
    user = conn.assigns[:current_user]

    token = Oauth.get_token!(user, token_id)

    render(conn, "oauth/revoke.html",
      token: token,
      changeset: Oauth.change_token(token)
    )
  end

  def new_application(conn, _) do
    render(conn, "oauth/application/new.html", changeset: Oauth.change_application(%Application{}))
  end

  def create_application(conn, %{"application" => application_params}) do
    user = conn.assigns[:current_user]

    user
    |> Oauth.create_application(application_params)
    |> case do
      {:ok, application} ->
        conn
        |> put_flash(:info, "Application created successfully.")
        |> render("oauth/application/show.html", application: application)

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "oauth/application/new.html", changeset: changeset)
    end
  end

  def edit_application(conn, %{"uid" => uid}) do
    user = conn.assigns[:current_user]

    application =
      user
      |> Oauth.get_application_for!(uid)

    changeset = application
                |> Oauth.change_application()

    render(conn, "oauth/application/edit.html", changeset: changeset, application: application)
  end

  def update_application(conn, %{"uid" => uid, "application" => params}) do
    user = conn.assigns[:current_user]

    application = Oauth.get_application_for!(user, uid)

    application
    |> Oauth.update_application(params)
    |> case do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Application updated succesfully.")
        |> redirect(to: Routes.oauth_path(conn, :show))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "oauth/application/edit.html", changeset: changeset, application: application)
    end
  end

  def delete_application(conn, %{"uid" => uid}) do
    user = conn.assigns[:current_user]

    {:ok, _application} =
      user
      |> Oauth.get_application_for!(uid)
      |> Oauth.delete_application()

    conn
    |> put_flash(:info, "Application deleted successfully.")
    |> redirect(to: Routes.oauth_path(conn, :show))
  end

  def new_authorization(conn, params) do
    user = conn.assigns[:current_user]

    user
    |> Oauth.preauthorize(params)
    |> case do
      {:ok, client, scopes} ->
        render(conn, "oauth/authorization/new.html",
          params: params,
          client: client,
          scopes: scopes
        )

      {:native_redirect, %{code: _code}} ->
        redirect(conn, to: Routes.oauth_path(conn, :show))

      {:redirect, redirect_uri} ->
        redirect(conn, external: redirect_uri)

      {:error, error, status} ->
        conn
        |> put_status(status)
        |> put_flash(:error, "An error occurred")
        |> render("oauth/authorization/error.html", error: error)
    end
  end

  def create_authorization(conn, params) do
    user = conn.assigns[:current_user]

    user
    |> Oauth.authorize(params)
    |> redirect_or_render(conn)
  end

  def delete_authorization(conn, params) do
    user = conn.assigns[:current_user]

    user
    |> Oauth.deny(params)
    |> redirect_or_render(conn)
  end

  def revoke_application(conn, %{"uid" => uid}) do
    user = conn.assigns[:current_user]

    user
    |> Oauth.get_application_for!(uid)
    |> Oauth.revoke_all_access_tokens_for(user)
    |> case do
         {:ok, []} ->
           conn
           |> put_flash(:info, "All tokens are revoked.")
         {:ok, tokens} ->
           conn
           |> put_flash(:info, "Revoked #{Enum.count(tokens)} tokens.")
       end
    |> redirect(to: Routes.oauth_path(conn, :edit_application, uid))
  end

  def reset_application(conn, %{"uid" => uid}) do
    user = conn.assigns[:current_user]

    user
    |> Oauth.get_application_for!(uid)
    |> Oauth.reset_secret()
    |> case do
         {:ok, application} ->
           conn
           |> put_flash(:info, "Application secret reset successfully.")
           |> render("oauth/application/show.html", application: application)
       end
  end

  defp redirect_or_render({:redirect, redirect_uri}, conn) do
    redirect(conn, external: redirect_uri)
  end

  defp redirect_or_render({:native_redirect, payload}, conn) do
    json(conn, payload)
  end

  defp redirect_or_render({:error, error, status}, conn) do
    conn
    |> put_status(status)
    |> json(error)
  end
end
