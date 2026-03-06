defmodule LinkhutWeb.Settings.OauthController do
  @moduledoc """
  Controller for OAuth management
  """
  use LinkhutWeb, :controller

  alias Linkhut.Oauth
  alias Linkhut.Oauth.Application

  @personal_access_token_scopes for(
                                  scope <- ~w(posts tags),
                                  access <- ~w(read write),
                                  do: "#{scope}:#{access}"
                                )
                                |> Enum.join(" ")

  def show(conn, _) do
    user = conn.assigns[:current_user]

    render(conn, :index,
      personal_access_tokens: Oauth.get_tokens(user),
      authorized_applications: Oauth.get_authorized_applications_for(user),
      applications: Oauth.get_applications_for(user)
    )
  end

  def new_personal_token(conn, _) do
    render(conn, :personal_token_new)
  end

  def create_personal_token(conn, %{"comment" => comment}) do
    user = conn.assigns[:current_user]

    token =
      Oauth.create_token!(user, %{
        comment: String.trim(comment),
        scopes: @personal_access_token_scopes
      })

    render(conn, :personal_token_show, token: token.token)
  end

  def revoke_token(conn, %{"id" => token_id, "access_token" => %{"id" => id}})
      when token_id == id do
    user = conn.assigns[:current_user]

    token =
      Oauth.get_token!(user, token_id)
      |> Oauth.revoke!()

    conn
    |> put_flash(:info, "Revoked token: #{String.slice(token.token, 0, 8)}...")
    |> redirect(to: ~p"/_/oauth")
  end

  def revoke_token(conn, %{"id" => token_id}) do
    user = conn.assigns[:current_user]

    token = Oauth.get_token!(user, token_id)

    render(conn, :revoke,
      token: token,
      changeset: Oauth.change_token(token)
    )
  end

  def new_application(conn, _) do
    render(conn, :application_new, changeset: Oauth.change_application(%Application{}))
  end

  def create_application(conn, %{"application" => application_params}) do
    user = conn.assigns[:current_user]

    user
    |> Oauth.create_application(application_params)
    |> case do
      {:ok, application} ->
        conn
        |> put_flash(:info, "Application created successfully.")
        |> render(:application_show,
          application: application,
          heading: "OAuth application registered",
          description:
            "Your OAuth application has been successfully registered. Write down this information:"
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :application_new, changeset: changeset)
    end
  end

  def edit_application(conn, %{"uid" => uid}) do
    user = conn.assigns[:current_user]

    application =
      user
      |> Oauth.get_application_for!(uid)

    changeset =
      application
      |> Oauth.change_application()

    render(conn, :application_edit, changeset: changeset, application: application)
  end

  def update_application(conn, %{"uid" => uid, "application" => params}) do
    user = conn.assigns[:current_user]

    application = Oauth.get_application_for!(user, uid)

    application
    |> Oauth.update_application(params)
    |> case do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Application updated successfully.")
        |> redirect(to: ~p"/_/oauth")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :application_edit,
          changeset: changeset,
          application: application
        )
    end
  end

  def delete_application(conn, %{"uid" => uid}) do
    user = conn.assigns[:current_user]

    case user |> Oauth.get_application_for!(uid) |> Oauth.delete_application() do
      {:ok, _application} ->
        conn
        |> put_flash(:info, "Application deleted successfully.")
        |> redirect(to: ~p"/_/oauth")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to delete application.")
        |> redirect(to: ~p"/_/oauth")
    end
  end

  def new_authorization(conn, params) do
    user = conn.assigns[:current_user]

    user
    |> Oauth.preauthorize(params)
    |> case do
      {:ok, client, scopes} ->
        render(conn, :authorization_new,
          params: params,
          client: client,
          scopes: scopes
        )

      {:native_redirect, %{code: _code}} ->
        redirect(conn, to: ~p"/_/oauth")

      {:redirect, redirect_uri} ->
        redirect(conn, external: redirect_uri)

      {:error, error, status} ->
        conn
        |> put_status(status)
        |> put_flash(:error, "An error occurred")
        |> render(:authorization_error, error: error)
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

    case user |> Oauth.get_application_for!(uid) |> Oauth.revoke_all_access_tokens_for(user) do
      {:ok, []} ->
        conn
        |> put_flash(:info, "All tokens are revoked.")
        |> redirect(to: ~p"/_/oauth/application/#{uid}/settings")

      {:ok, tokens} ->
        conn
        |> put_flash(:info, "Revoked #{Enum.count(tokens)} tokens.")
        |> redirect(to: ~p"/_/oauth/application/#{uid}/settings")

      {:error, _} ->
        conn
        |> put_flash(:error, "Failed to revoke tokens.")
        |> redirect(to: ~p"/_/oauth/application/#{uid}/settings")
    end
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
        |> render(:application_show,
          application: application,
          heading: "Application secret reset",
          description: "Your application secret has been reset. Write down the new secret:"
        )

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to reset application secret.")
        |> redirect(to: ~p"/_/oauth/application/#{uid}/settings")
    end
  end

  def revoke_access(conn, %{"uid" => uid}) do
    user = conn.assigns[:current_user]

    app = Oauth.get_application!(uid)

    case Oauth.revoke_all_access_tokens_for(app, user) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Revoked access to '#{app.name}'")
        |> redirect(to: ~p"/_/oauth")

      {:error, _} ->
        conn
        |> put_flash(:error, "Failed to revoke access.")
        |> redirect(to: ~p"/_/oauth")
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
