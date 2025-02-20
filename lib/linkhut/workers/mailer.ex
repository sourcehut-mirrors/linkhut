defmodule Linkhut.Workers.MailerWorker do
  use Oban.Worker, queue: :mailer
  import Swoosh.Email

  alias Linkhut.Mailer

  def send(recipient, subject, body) do
    %{recipient: recipient, subject: subject, body: body}
    |> Linkhut.Workers.MailerWorker.new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"recipient" => recipient, "subject" => subject, "body" => body}}) do
    email =
      new()
      |> to(recipient)
      |> from(Keyword.get(Linkhut.Config.mail(), :sender))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
