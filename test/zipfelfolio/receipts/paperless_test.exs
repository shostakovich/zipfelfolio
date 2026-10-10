defmodule Zipfelfolio.Receipts.PaperlessTest do
  use Zipfelfolio.DataCase

  # Failing instances and documents are logged.
  @moduletag :capture_log

  import Zipfelfolio.{ReceiptsFixtures, UsersFixtures}

  alias Zipfelfolio.{FakeModel, FakePaperless, FakeTextExtractor, Receipts, Users}
  alias Zipfelfolio.Portfolios.Receipt
  alias Zipfelfolio.Receipts.PaperlessJob
  alias Zipfelfolio.Users.{Scope, User}

  @url "http://paperless.test"

  defp paperless_user(tag, url \\ @url, token \\ "token") do
    {:ok, user} =
      Users.update_paperless(user_scope_fixture(), %{
        "paperless_url" => url,
        "paperless_token" => token,
        "paperless_tag" => tag
      })

    user
  end

  defp inbox(user), do: Receipts.list_inbox(Scope.for_user(user))

  defp tags(id), do: FakePaperless.documents(@url) |> Enum.find(&(&1.id == id)) |> Map.get(:tags)

  defp poll_all do
    PaperlessJob.poll_all()
    await_recognition()
  end

  setup do
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    :ok
  end

  test "takes only documents with the user's tag, swaps the tag and assigns them to the user who configured it" do
    robert = paperless_user("zipfelfolio")
    sebastian = paperless_user("sebastian")

    FakePaperless.serve(%{
      @url => %{
        token: "token",
        documents: [
          FakePaperless.document(4812, ["zipfelfolio", "Bank"]),
          FakePaperless.document(4813, ["sebastian"], filename: nil),
          FakePaperless.document(4814, ["Rechnung"])
        ]
      }
    })

    poll_all()

    assert [%Receipt{paperless_id: 4812, filename: "scan-4812.pdf", status: :ready}] =
             inbox(robert)

    assert [%Receipt{paperless_id: 4813, filename: "Paperless 4813.pdf"}] = inbox(sebastian)
    assert tags(4812) == ["Bank", "zipfelfolio-erledigt"]
    assert tags(4813) == ["sebastian-erledigt"]
    assert tags(4814) == ["Rechnung"]
    assert Repo.get!(User, robert.id).paperless_polled_at
  end

  test "Scenario: Paperless tag swapped — a document in the inbox is tagged „-erledigt“ instead" do
    user = paperless_user("zipfelfolio")

    FakePaperless.serve(%{
      @url => %{token: "token", documents: [FakePaperless.document(1, ["zipfelfolio"])]}
    })

    poll_all()
    assert [_receipt] = inbox(user)
    assert tags(1) == ["zipfelfolio-erledigt"]

    poll_all()
    assert [_one] = inbox(user)
  end

  test "a document whose tag swap failed lands once and has its tag swapped on the next poll" do
    user = paperless_user("zipfelfolio")
    document = FakePaperless.document(1, ["zipfelfolio"], swap_fails: true)
    FakePaperless.serve(%{@url => %{token: "token", documents: [document]}})

    poll_all()
    assert [_receipt] = inbox(user)
    assert tags(1) == ["zipfelfolio"]

    FakePaperless.update_document(@url, 1, swap_fails: false)
    poll_all()

    assert [_one] = inbox(user)
    assert tags(1) == ["zipfelfolio-erledigt"]
  end

  test "a discarded document stays discarded while its tag swap keeps failing" do
    user = paperless_user("zipfelfolio")
    document = FakePaperless.document(1, ["zipfelfolio"], swap_fails: true)
    FakePaperless.serve(%{@url => %{token: "token", documents: [document]}})

    poll_all()
    [receipt] = inbox(user)
    :ok = Receipts.discard(Scope.for_user(user), receipt.id)

    poll_all()
    poll_all()

    assert inbox(user) == []
    assert Repo.get!(Receipt, receipt.id).status == :discarded

    FakePaperless.update_document(@url, 1, swap_fails: false)
    poll_all()

    assert inbox(user) == []
    assert tags(1) == ["zipfelfolio-erledigt"]
  end

  test "has the model read Paperless' text, not the PDF's" do
    FakeTextExtractor.stub("pdftotext")
    user = paperless_user("zipfelfolio")
    document = FakePaperless.document(1, ["zipfelfolio"], content: receipt_text("PL-1"))
    FakePaperless.serve(%{@url => %{token: "token", documents: [document]}})

    poll_all()

    assert_received {:answer, text}
    assert text == receipt_text("PL-1")
    assert [%Receipt{text: ^text}] = inbox(user)
  end

  test "reads the PDF's text when Paperless has none" do
    FakeTextExtractor.stub("pdftotext")
    paperless_user("zipfelfolio")
    document = FakePaperless.document(1, ["zipfelfolio"], content: "  ")
    FakePaperless.serve(%{@url => %{token: "token", documents: [document]}})

    poll_all()

    assert_received {:answer, "pdftotext"}
  end

  test "a file uploaded already lands once and still loses its tag" do
    user = paperless_user("zipfelfolio")
    document = FakePaperless.document(1, ["zipfelfolio"])
    path = pdf_file("beleg.pdf", document.pdf)
    {:ok, :added} = Receipts.upload(Scope.for_user(user), path, "beleg.pdf")
    FakePaperless.serve(%{@url => %{token: "token", documents: [document]}})

    poll_all()

    assert [%Receipt{filename: "beleg.pdf"}] = inbox(user)
    assert tags(1) == ["zipfelfolio-erledigt"]
  end

  test "one failing instance or document, or one too large, does not stop the others" do
    unreachable = paperless_user("zipfelfolio", "http://unreachable.test")
    wrong_token = paperless_user("zipfelfolio", @url, "wrong")
    user = paperless_user("zipfelfolio")

    FakePaperless.serve(%{
      @url => %{
        token: "token",
        documents: [
          FakePaperless.document(1, ["zipfelfolio"], raise: true),
          FakePaperless.document(2, ["zipfelfolio"], pdf: "no PDF"),
          FakePaperless.document(3, ["zipfelfolio"]),
          FakePaperless.document(4, ["zipfelfolio"],
            pdf: "%PDF-1.4\n" <> String.duplicate(" ", 20_000_000)
          )
        ]
      }
    })

    poll_all()

    assert [%Receipt{paperless_id: 3}] = inbox(user)
    assert tags(1) == ["zipfelfolio"]
    assert tags(2) == ["zipfelfolio"]
    assert tags(4) == ["zipfelfolio"]
    assert inbox(unreachable) == [] and inbox(wrong_token) == []
    refute Repo.get!(User, unreachable.id).paperless_polled_at
  end
end
