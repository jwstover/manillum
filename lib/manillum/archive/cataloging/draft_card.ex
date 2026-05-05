defmodule Manillum.Archive.Cataloging.DraftCard do
  @moduledoc """
  Typed struct mirroring the LLM-output half of the §7.1 Draft Card contract.

  This is the **return type only** of the `:extract_drafts` prompt-backed
  action on `Manillum.Archive.Capture`. The orchestration change
  (`Manillum.Archive.Capture.Changes.RunCataloging`) consumes a list of
  these and writes persisted draft `Card` rows that additionally carry
  `capture_id`, pipeline-derived metadata, and `status: :draft`.

  Field shapes match Card's enums so AshAI can enforce structured output:

    * `card_type` — one of `:person | :event | :place | :concept | :source | :date | :artifact`
    * `drawer` — one of the seven era codes from §7.4
    * `date_token` / `slug` / `front` / `back` — strings per §7.4 / §4
    * `tags` — list of human-readable tag names (e.g. "Bronze Age")
    * `entities` — list of proper-noun mentions in the back text
      (people / places / sources, excluding the card's own subject).
      Persisted on `Card.entities` as denormalized search/filter
      metadata and consumed by the reactive cross-reference scan
      (M-34) at file-time.

  See spec §7.1 for the contract surface this mirrors and §5 Stream C for
  how it slots into the pipeline.
  """

  use Ash.TypedStruct

  typed_struct do
    field :card_type, :atom,
      allow_nil?: false,
      constraints: [one_of: [:person, :event, :place, :concept, :source, :date, :artifact]]

    field :drawer, :atom,
      allow_nil?: false,
      constraints: [one_of: [:ANT, :CLA, :MED, :REN, :EAR, :MOD, :CON]]

    field :date_token, :string, allow_nil?: false
    field :slug, :string, allow_nil?: false
    field :front, :string, allow_nil?: false
    field :back, :string, allow_nil?: false

    field :tags, {:array, :string}, default: []
    field :entities, {:array, :string}, default: []
  end
end
