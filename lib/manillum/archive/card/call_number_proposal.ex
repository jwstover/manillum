defmodule Manillum.Archive.Card.CallNumberProposal do
  @moduledoc """
  Result of `Manillum.Archive.Card.propose_call_number`.

  Two shapes, discriminated by `:status`:

    * `:resolved` — `drawer`, `date_token`, `slug`, and `call_number` are
      populated; `existing_card_id` is nil. The proposed segments are
      unique for the user and can be used to draft a card.

    * `:collision` — the requested segments collide with an existing card
      for the user. `existing_card_id` is the colliding card's UUID; the
      caller decides what to do (edit the slug, discard the draft, surface
      the existing card to the user).

  This action is **detection-only**. It does not generate alternative
  slugs — picking a meaningful disambiguator requires content context
  (the card's `front` / `back` / entities) that lives at the cataloging
  pipeline or the filing tray, not here. See spec §7.4 for the
  disambiguation style guide.
  """

  use Ash.TypedStruct

  typed_struct do
    field :status, :atom, allow_nil?: false, constraints: [one_of: [:resolved, :collision]]
    field :drawer, :atom
    field :date_token, :string
    field :slug, :string
    field :call_number, :string
    field :existing_card_id, :uuid
  end
end
