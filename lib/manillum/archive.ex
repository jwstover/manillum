defmodule Manillum.Archive do
  @moduledoc """
  The card archive: filed Cards, their Capture provenance, and (later)
  Tags / Links / CallNumberRedirects.

  See spec §4 for the resource shapes and §7.4 for the call_number format.
  """

  use Ash.Domain, otp_app: :manillum, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Manillum.Archive.Card do
      define :draft_card, action: :draft
      define :file_card, action: :file
      define :propose_call_number, action: :propose_call_number
    end

    resource Manillum.Archive.Capture do
      # Public submit entry point — LiveView calls this on `+ FILE` and
      # walks away. The AshOban trigger picks the row up by status and
      # drives the rest. Spec §5 Stream C interface line refers to this
      # as `Manillum.Archive.create!(:submit, %{...})`; the equivalent
      # idiomatic call is `Manillum.Archive.submit!(%{...})`.
      define :submit, action: :submit

      # Sync prompt-backed action exposed for `/notebooks/cataloging.livemd`
      # iteration and for tests. Bypasses Oban + DB entirely.
      define :extract_drafts, action: :extract_drafts, args: [:source_text]
    end

    resource Manillum.Archive.Tag do
      define :find_or_create_tag, action: :find_or_create, args: [:user_id, :name]
    end

    resource Manillum.Archive.CardTag do
      define :tag_card, action: :tag_card, args: [:card_id, :tag_id]
      define :untag_card, action: :destroy
    end

    resource Manillum.Archive.Link do
      define :link, action: :link
      define :unlink, action: :destroy
    end
  end
end
