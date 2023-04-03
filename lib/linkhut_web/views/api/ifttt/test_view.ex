defmodule LinkhutWeb.Api.IFTTT.TestView do
  @moduledoc false
  use LinkhutWeb, :view

  def render("setup.json", %{
        token: token,
        public_url: public_url,
        private_url: private_url,
        date_time: date_time
      }) do
    %{
      data: %{
        accessToken: token,
        samples: %{
          actions: %{
            add_public_link: %{
              url: public_url,
              tags: "ifttt test unread",
              notes: "Testing IFTTT integration on #{date_time}",
              title: "IFTTT Test"
            },
            add_private_link: %{
              url: private_url,
              tags: "ifttt test",
              notes: "Testing IFTTT integration on #{date_time}",
              title: "IFTTT Test"
            }
          },
          actionRecordSkipping: %{
            add_public_link: %{
              url: "",
              tags: "ifttt test unread",
              notes: "Testing IFTTT integration on #{date_time}",
              title: "IFTTT Test"
            },
            add_private_link: %{
              url: "",
              tags: "ifttt test",
              notes: "Testing IFTTT integration on #{date_time}",
              title: "IFTTT Test"
            }
          },
          triggers: %{
            new_public_link_tagged: %{
              tag: "linkhut"
            }
          }
        }
      }
    }
  end
end
