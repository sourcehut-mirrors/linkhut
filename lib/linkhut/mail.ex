defmodule Linkhut.Mail do
  @moduledoc """
  Delivers transactional emails via background jobs.
  """

  @doc """
  Enqueues an email for background delivery.

  Returns `{:ok, %Oban.Job{}}` on success.
  """
  @spec deliver(String.t(), String.t(), String.t()) ::
          {:ok, Oban.Job.t()} | {:error, Oban.Job.changeset()}
  def deliver(recipient, subject, body) do
    Linkhut.Mail.Worker.enqueue(recipient, subject, body)
  end

  @doc """
  Returns the configured sender tuple, e.g. `{"linkhut", "no-reply@example.com"}`.
  """
  def sender do
    Linkhut.Config.mail(:sender)
  end
end
