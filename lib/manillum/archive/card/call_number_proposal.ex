defmodule Manillum.Archive.Card.CallNumberProposal do
  @moduledoc """
  Result of `Manillum.Archive.Card.propose_call_number`.

  Two shapes, discriminated by `:status`:

    * `:resolved` — `drawer`, `date_token`, `slug`, and `call_number` are
      populated; `suggestions` is `[]`. The proposed segments are unique
      for the user and can be used to draft a card.

    * `:collision` — the requested segments collide with an existing card
      for the user. `suggestions` is a non-empty list of
      `{slug, reason}` tuples. The discriminator picks alternatives based
      on `card_type` per spec §7.4 (letter suffix for people, year
      disambiguator for events, qualifier for places, numeric otherwise).

  The format string in `:call_number` always matches §7.4 byte-for-byte —
  see `Manillum.Archive.Card.format_call_number/3`.
  """

  use Ash.TypedStruct

  typed_struct do
    field :status, :atom, allow_nil?: false, constraints: [one_of: [:resolved, :collision]]
    field :drawer, :atom
    field :date_token, :string
    field :slug, :string
    field :call_number, :string
    field :suggestions, {:array, :map}, default: []
  end
end
