defmodule Linkhut.Accounts.UserNotifier do
  import Swoosh.Email

  alias Linkhut.Mailer

  defp signature() do
    "-- \nadmin at ln.ht\n"
  end

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
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

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user.credential.email, "Confirmation instructions", """
    Hi #{user.username},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    #{signature()}
    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.credential.email, "Reset password instructions", """
    Hi #{user.username},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    #{signature()}
    """)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.credential.unconfirmed_email, "Confirm your linkhut email address change", """
    Hello #{user.username},

    You (or someone pretending to be you) have changed the email on your
    account to #{user.credential.unconfirmed_email}. To confirm the new email and apply the change,
    click the following link:

    #{url}

    If you didn't request this change, please ignore this.

    #{signature()}
    """)
  end
end
