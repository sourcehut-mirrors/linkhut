defmodule Linkhut.Accounts.UserNotifier do
  defp signature() do
    "-- \nlinkhut admin at #{LinkhutWeb.Endpoint.url}"
  end

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    with {:ok, %{args: args}} <- Linkhut.Workers.MailerWorker.send(recipient, subject, body) do
      {:ok, args}
    end
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user.credential.email, "Confirmation instructions", """
    Hello #{user.username},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    #{signature()}

    You’re receiving this email because someone signed up for a linkhut account using this email address.
    If that wasn’t you, feel free to ignore this message.
    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.credential.email, "Reset password instructions", """
    Hello #{user.username},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    #{signature()}

    You’re receiving this email because someone requested a password reset for your linkhut account.
    If that wasn’t you, you can safely ignore this message.
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

    You’re receiving this email because you updated your email on linkhut (#{LinkhutWeb.Endpoint.url}).
    If you didn’t do this, ignore this message or contact support.
    """)
  end
end
