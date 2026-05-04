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
    resource Manillum.Archive.Card
    resource Manillum.Archive.Capture
  end
end
