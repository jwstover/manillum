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
    defaults [:read, :destroy]

    create :draft do
      description """
      Create a card in `:draft` status. Used by the cataloging pipeline
      (Slice 4 sets `capture_id`) and by direct creation in IEx / tests.
      Drafts get promoted to `:filed` via the `:file` action (M-17).
      """

      accept [
        :user_id,
        :capture_id,
        :drawer,
        :date_token,
        :slug,
        :card_type,
        :front,
        :back,
        :entities
      ]

      change set_attribute(:status, :draft)
    end

    update :file do
      description """
      Promote a `:draft` Card to `:filed`. Rejects any current status other
      than `:draft`. Spec §5 Stream B task 2 also calls for kicking off
      async embedding generation and creating tag/link associations from
      this action; those land in Slice 4 / Gate B.2 / B.3. For Gate B.1
      this is just the status transition.

      Note on uniqueness: the DB-level identity on `(user_id, drawer, slug)`
      is the source of truth and applies to drafts as well as filed cards.
      Filing doesn't change segments, so it can't introduce a collision —
      the cataloging pipeline (Slice 4) calls `:propose_call_number` first
      and disambiguates the slug before drafting.
      """

      accept []
      require_atomic? false

      validate attribute_equals(:status, :draft) do
        message "Card must be in :draft status to be filed (current: %{value})."
      end

      change set_attribute(:status, :filed)
    end

    update :rename do
      description """
      Change one or more of `drawer` / `date_token` / `slug`. Validates the
      new combination against the `:unique_call_number` identity, writes a
      `Manillum.Archive.CallNumberRedirect` for the **old** segments
      pointing at this card, and broadcasts `{:card_renamed, old, new}` on
      `"user:\#{user_id}:archive"` per spec §7.3.

      Acceptable on cards in any status — the rename mechanic is what
      makes retroactive disambiguation possible (per §7.4 / spec note on
      `JULIUS-CAESAR` flow).
      """

      accept [:drawer, :date_token, :slug]
      require_atomic? false

      change Manillum.Archive.Card.Changes.Rename
    end

    action :propose_call_number, Manillum.Archive.Card.CallNumberProposal do
      description """
      Pure read action: given a user + segments + card_type, check whether
      the (user_id, drawer, date_token, slug) combination is unique. On
      success returns a `:resolved` proposal with the formatted call_number;
      on collision returns a `:collision` proposal with disambiguation
      suggestions per §7.4.
      """

      argument :user_id, :uuid, allow_nil?: false

      argument :drawer, :atom do
        allow_nil? false
        constraints one_of: [:ANT, :CLA, :MED, :REN, :EAR, :MOD, :CON]
      end

      argument :date_token, :string, allow_nil?: false
      argument :slug, :string, allow_nil?: false

      argument :card_type, :atom do
        allow_nil? false
        constraints one_of: [:person, :event, :place, :concept, :source, :date, :artifact]
      end

      run Manillum.Archive.Card.ProposeCallNumber
    end
  end

  @doc """
  Format a call_number from its segments. Mirrors the SQL calculation
  (spec §7.4): `[DRAWER] · [DATE] · [SLUG]` with U+00B7 middle-dot
  separator and single ASCII spaces.
  """
  @spec format_call_number(atom(), String.t(), String.t()) :: String.t()
  def format_call_number(drawer, date_token, slug)
      when is_atom(drawer) and is_binary(date_token) and is_binary(slug) do
    "#{drawer} · #{date_token} · #{slug}"
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

    attribute :entities, {:array, :string} do
      default []
      allow_nil? false
      public? true

      description """
      Proper-noun mentions extracted from the back text by the cataloging
      pipeline (named actors, places, sources — excluding the card's own
      subject). Denormalized search/filter metadata; consumed by the
      reactive cross-reference scan at file-time. Not link targets — the
      project deliberately does not create speculative Card stubs from
      this list.
      """
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

    many_to_many :tags, Manillum.Archive.Tag do
      through Manillum.Archive.CardTag
      source_attribute_on_join_resource :card_id
      destination_attribute_on_join_resource :tag_id
    end

    has_many :outgoing_links, Manillum.Archive.Link do
      destination_attribute :from_card_id
    end

    has_many :incoming_links, Manillum.Archive.Link do
      destination_attribute :to_card_id
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
    # Per spec §7.4 (clarified): the call_number as a whole is unique per
    # user — i.e. (drawer, date_token, slug) together. Two cards with the
    # same drawer + slug but different date_tokens coexist naturally; only
    # full-segment collisions trigger disambiguation in `:propose_call_number`.
    identity :unique_call_number, [:user_id, :drawer, :date_token, :slug]
  end
end
