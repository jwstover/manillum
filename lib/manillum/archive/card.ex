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
  M-15/M-16/M-17. The `embedding` column + vectorize block ship in
  Slice 6 (M-24) alongside the dup-detection pipeline.

  ## Embeddings

  `back` is vectorized into `:embedding` (1536 dims via
  `Manillum.AI.Embedding.OpenAI`) using the `:ash_oban` strategy:
  creates and `back`-changing updates enqueue an
  `:ash_ai_update_embeddings` job on the `:card_vectorizer` queue,
  which calls the OpenAI embeddings endpoint and writes the vector
  back to the row. Status flips and renames don't touch `back`, so
  they don't trigger regeneration. The HNSW cosine-similarity index
  is added by `priv/repo/migrations/*_add_card_embedding_hnsw_index.exs`
  and powers `Manillum.Archive.find_duplicates/2`.
  """

  use Ash.Resource,
    otp_app: :manillum,
    domain: Manillum.Archive,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAi, AshOban]

  postgres do
    table "cards"
    repo Manillum.Repo

    # Translate the partial-index `where` clause on `:unique_call_number`
    # to SQL for the migration generator. Must stay in sync with the
    # identity's `where: expr(status != :draft)` below.
    identity_wheres_to_sql unique_call_number: "status != 'draft'"
  end

  vectorize do
    attributes back: :embedding
    strategy :ash_oban
    embedding_model Manillum.AI.Embedding.OpenAI
  end

  oban do
    triggers do
      trigger :ash_ai_update_embeddings do
        action :ash_ai_update_embeddings
        queue :card_vectorizer
        scheduler_cron false
        worker_read_action :read
        worker_module_name Manillum.Archive.Card.AshOban.Worker.UpdateEmbeddings
        scheduler_module_name Manillum.Archive.Card.AshOban.Scheduler.UpdateEmbeddings
      end
    end
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
        :entities,
        :duplicate_candidate_ids,
        :collision_card_id
      ]

      change set_attribute(:status, :draft)
    end

    update :file do
      description """
      Promote a `:draft` Card to `:filed`. Rejects any current status other
      than `:draft`.

      Note on uniqueness: the DB-level
      `unique_call_number` identity on `(user_id, drawer, date_token, slug)`
      is scoped to non-draft cards (Slice 6 / M-24). Drafts may coexist with
      colliding segments — the cataloging pipeline persists them with
      `collision_card_id` set, and the filing tray gates the file affordance
      until the user resolves the collision (typically by renaming the
      colliding card or this draft via `:rename`). Filing a still-colliding
      draft will fail at the DB level as a safety net.
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

    attribute :duplicate_candidate_ids, {:array, :uuid} do
      default []
      allow_nil? false
      public? true

      description """
      Draft-phase metadata: ids of existing filed cards that are
      semantically near-duplicates of this draft (cosine similarity over
      `Manillum.Archive.find_duplicates/2`'s threshold). Populated by the
      cataloging pipeline alongside the draft Card row. The filing tray
      surfaces these as "this looks similar to existing card X" warnings;
      the user resolves by editing the slug, discarding the draft, or
      filing anyway. Empty list once the user has reviewed.
      """
    end

    attribute :collision_card_id, :uuid do
      public? true

      description """
      Draft-phase metadata: id of an existing Card whose
      `(drawer, date_token, slug)` segments match this draft's. Set by
      the cataloging pipeline when `:propose_call_number` returns
      `:collision`; the draft is persisted with content but flagged so
      the filing tray can show it alongside the colliding card and let
      the user pick disambiguating segments before filing. `nil` for
      drafts whose call_number resolved cleanly.
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
    #
    # Scoped to non-draft cards (Slice 6 / M-24): drafts may persist with
    # colliding segments and a `collision_card_id` flag so the filing tray
    # can surface them; the constraint applies once a card is filed and
    # the segments become canonical.
    identity :unique_call_number, [:user_id, :drawer, :date_token, :slug],
      where: expr(status != :draft)
  end
end
