defmodule Linkhut.Mail.WorkerTest do
  use Linkhut.DataCase, async: true

  alias Linkhut.Mail.Worker

  describe "perform/1" do
    test "delivers an email with correct fields" do
      job = %Oban.Job{
        args: %{
          "recipient" => "user@example.com",
          "subject" => "Test Subject",
          "body" => "Hello, world!"
        }
      }

      assert {:ok, %Swoosh.Email{} = email} = Worker.perform(job)
      assert email.to == [{"", "user@example.com"}]
      assert email.from == {"linkhut", "no-reply@example.com"}
      assert email.subject == "Test Subject"
      assert email.text_body == "Hello, world!"
    end
  end

  describe "enqueue/3" do
    test "inserts an Oban job with correct args" do
      assert {:ok, %Oban.Job{} = job} =
               Worker.enqueue("user@example.com", "Test", "Body")

      # In Oban manual test mode, args retain atom keys before JSON serialization.
      # In production, they become string keys after round-tripping through the DB.
      assert job.args[:recipient] == "user@example.com"
      assert job.args[:subject] == "Test"
      assert job.args[:body] == "Body"
      assert job.queue == "mailer"
      assert job.max_attempts == 5
    end
  end
end
