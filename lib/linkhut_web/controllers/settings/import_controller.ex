defmodule LinkhutWeb.Settings.ImportController do
  use LinkhutWeb, :controller

  @moduledoc """
  Controller for importing bookmarks
  """
  alias Linkhut.Workers.ImportWorker
  alias Linkhut.Jobs

  def show(conn, _) do
    render(conn, :import_page)
  end

  def upload(conn, %{
        "upload" => %{"file" => %Plug.Upload{content_type: "text/html", path: file} = upload}
      }) do
    user = conn.assigns[:current_user]
    Plug.Upload.give_away(upload, ImportWorker.get_pid())
    {:ok, import} = ImportWorker.enqueue(user, file)

    conn
    |> redirect(to: ~p"/_/import/#{import.job_id}")
  end

  def status(conn, %{"task" => task}) do
    user = conn.assigns[:current_user]

    case Jobs.get_import(user.id, task) do
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
      %{state: :in_progress} ->
        conn
        |> Plug.Conn.put_resp_header("Refresh", "10")

      _ ->
        conn
    end
  end
end
