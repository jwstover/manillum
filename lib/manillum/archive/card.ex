defmodule Manillum.Archive.Card do
  @moduledoc """
  An atomic fact card in the user's archive. Identified by a `call_number`
  derived from `drawer`, `date_token`, and `slug` (format defined in spec
  §7.4: `[DRAWER] · [DATE] · [SLUG]` with a U+00B7 middle-dot separator
  flanked by single ASCII spaces).

  The unique identity is on `(user_id, drawer, date_token, slug)` —
  `call_number` is a calculation, not a stored attribute. Lookup by
  call-number string parses the format back into segments.

  Slice 3 lands the resource skeleton with `:read` defaults. Stream B's
  CRUD actions (`:draft`, `:propose_call_number`, `:file`) follow in
  M-15/M-16/M-17. The `embedding` column and vectorize block ship in
  Slice 4 alongside the cataloging pipeline.
  """

  use Ash.Resource,
    otp_app: :manillum,
    domain: Manillum.Archive,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "cards"
    repo Manillum.Repo
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id

    attribute :drawer, :atom do
      allow_nil? false
      constraints one_of: [:ANT, :CLA, :MED, :REN, :EAR, :MOD, :CON]
      public? true
    end

    attribute :date_token, :string do
      allow_nil? false
      public? true
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
    end

    attribute :card_type, :atom do
      allow_nil? false
      constraints one_of: [:person, :event, :place, :concept, :source, :date, :artifact]
      public? true
    end

    attribute :front, :string do
      allow_nil? false
      public? true
    end

    attribute :back, :string do
      allow_nil? false
      public? true
    end

    attribute :status, :atom do
      default :draft
      allow_nil? false
      constraints one_of: [:draft, :filed, :archived]
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Manillum.Accounts.User do
      allow_nil? false
      public? true
    end

    belongs_to :capture, Manillum.Archive.Capture do
      public? true
    end
  end

  calculations do
    # Format defined in spec §7.4: U+00B7 middle-dot separator, single
    # ASCII space on each side. The literal `·` in the fragment string is
    # the UTF-8 encoding of U+00B7.
    calculate :call_number,
              :string,
              expr(fragment("? || ' · ' || ? || ' · ' || ?", drawer, date_token, slug))
  end

  identities do
    # Unique per user — the segment combination is the canonical identity that
    # backs call_number uniqueness per spec §7.4.
    identity :unique_segments, [:user_id, :drawer, :date_token, :slug]
  end
end
