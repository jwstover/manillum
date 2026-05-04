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
        :back
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
    # Per spec §7.4: "Slug must be unique within a drawer for a given user."
    # Two cards with the same drawer + slug collide regardless of
    # date_token; disambiguation is handled by `:propose_call_number`.
    identity :unique_drawer_slug, [:user_id, :drawer, :slug]
  end
end
