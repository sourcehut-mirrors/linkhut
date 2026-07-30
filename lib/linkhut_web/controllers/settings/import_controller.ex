defmodule LinkhutWeb.Settings.ImportController do
  use LinkhutWeb, :controller

  @moduledoc """
  Controller for importing bookmarks
  """
  alias Linkhut.DataTransfer

  def show(conn, _) do
    render(conn, :import_export)
  end

  def upload(conn, %{
        "upload" => %{"file" => %Plug.Upload{content_type: "text/html", path: file}} = params
      }) do
    user = conn.assigns[:current_user]

    if DataTransfer.has_active_import?(user.id) do
      conn
      |> put_flash(
        :error,
        "You already have an import in progress. Please wait for it to finish."
      )
      |> redirect(to: ~p"/_/import")
    else
      case DataTransfer.create_import(user, file, Map.take(params, ["is_private"])) do
        {:ok, import} ->
          redirect(conn, to: ~p"/_/import/#{import.job_id}")

        {:error, _} ->
          conn
          |> put_flash(:error, "Couldn't start the import, try again")
          |> redirect(to: ~p"/_/import")
      end
    end
  end

  def upload(conn, _) do
    conn
    |> put_flash(:error, "Please select a file to upload.")
    |> redirect(to: ~p"/_/import")
  end

  def status(conn, %{"task" => task}) do
    user = conn.assigns[:current_user]

    case DataTransfer.get_import(user.id, task) do
      job when not is_nil(job) ->
        conn
        |> maybe_auto_refresh(job)
        |> render(:import_job, job: job)

      nil ->
        conn
        |> redirect(to: ~p"/_/import")
    end
  end

  defp maybe_auto_refresh(conn, job) do
    case job do
      %{state: state} when state in [:queued, :in_progress] ->
        conn
        |> Plug.Conn.put_resp_header("Refresh", "5")

      _ ->
        conn
    end
  end
end
