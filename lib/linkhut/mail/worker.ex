defmodule Linkhut.Mail.Worker do
  @moduledoc false
  use Oban.Worker, queue: :mailer, max_attempts: 5
  import Swoosh.Email

  alias Linkhut.Mail

  def enqueue(recipient, subject, body) do
    %{recipient: recipient, subject: subject, body: body}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"recipient" => recipient, "subject" => subject, "body" => body}}) do
    email =
      new()
      |> to(recipient)
      |> from(Mail.sender())
      |> subject(subject)
      |> text_body(body)

    case Mail.Mailer.deliver(email) do
      {:ok, _metadata} -> {:ok, email}
      {:error, reason} -> {:error, reason}
    end
  end
end
