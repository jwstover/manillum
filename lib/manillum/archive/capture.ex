defmodule Manillum.Archive.Capture do
  @moduledoc """
  A chunk of conversation text the user submitted for cataloging. Both
  the **input** to the cataloging pipeline (LiveView creates it on `+ FILE`)
  and the **audit record** that draft Cards link back to via
  `Card.capture_id` for provenance.

  Lifecycle: `:pending → :cataloging → :catalogued | :failed`. Captures
  remain in the DB after cataloging; the filing UI loads them via
  `Card.capture` for "back to source conversation" navigation.

  An AshOban scan trigger (`where expr(status == :pending)`) drives the
  `:catalog` update action, which delegates to
  `Manillum.Archive.Capture.Changes.RunCataloging`. See spec §5 Stream C
  for the full pipeline contract.

  ## Conversation / message references

  `conversation_id` and `message_id` are stored as plain UUIDs for now —
  Stream D (chat scaffold) hasn't landed the `Manillum.Conversations`
  domain yet, so we can't make them belongs_to relationships without
  introducing a phantom resource. The columns and constraints are sized
  correctly; converting to belongs_to in Stream D is a non-breaking
  resource-level change.

  ## Duplicate detection

  Per the Slice 4 review, semantic duplicate detection (embedding +
  cosine search via `Archive.find_duplicates/2`) is deferred to a
  follow-on. The pipeline lands here without that step; collisions on
  the `(user_id, drawer, date_token, slug)` identity are surfaced via
  `:propose_call_number` and the colliding draft is recorded but skipped
  rather than persisted (see `RunCataloging` for details).
  """

  use Ash.Resource,
    otp_app: :manillum,
    domain: Manillum.Archive,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAi, AshOban]

  postgres do
    table "captures"
    repo Manillum.Repo
  end

  oban do
    triggers do
      trigger :catalog do
        action :catalog
        queue :cataloging
        scheduler_cron "* * * * *"
        where expr(status == :pending)
        worker_read_action :read
        # The :catalog action makes a multi-second LLM call. Holding a row
        # lock that long blocks observers and risks transaction timeouts;
        # the trigger filter (status == :pending) plus the :mark_cataloging
        # update inside RunCataloging is sufficient to keep concurrent
        # scheduler ticks from re-picking the row.
        lock_for_update? false
        max_attempts 3
        worker_module_name Manillum.Archive.Capture.AshOban.Worker.Catalog
        scheduler_module_name Manillum.Archive.Capture.AshOban.Scheduler.Catalog
      end
    end
  end

  actions do
    defaults [:read]

    create :submit do
      description """
      Public entry point. LiveView calls `Manillum.Archive.create!(:submit, %{...})`
      from the chat surface (whole / block / selection filing) and walks
      away. The AshOban trigger picks the row up by status and drives the
      rest of the pipeline asynchronously.

      The capture is created in `:pending` status; `:cataloging` /
      `:catalogued` / `:failed` are owned by `Manillum.Archive.Capture.Changes.RunCataloging`.
      """

      accept [
        :user_id,
        :source_text,
        :scope,
        :selection_start,
        :selection_end,
        :conversation_id,
        :message_id
      ]

      change set_attribute(:status, :pending)
    end

    action :extract_drafts, {:array, Manillum.Archive.Cataloging.DraftCard} do
      description """
      Synchronous prompt-backed action. Given `source_text`, returns a
      list of `Manillum.Archive.Cataloging.DraftCard`s extracted by the
      LLM. **The Livebook (`/notebooks/cataloging.livemd`) calls this
      directly** — no DB row, no Oban, no PubSub — to iterate prompt
      quality against Gate C.1 fixtures.

      The orchestration change (`RunCataloging`) also calls this from the
      `:catalog` update action via `Capture.extract_drafts!/1`. AshAI
      enforces structured output by deriving the JSON schema from the
      `DraftCard` typed struct.
      """

      argument :source_text, :string do
        allow_nil? false

        description "The captured conversation text to catalog into atomic Draft Cards."
      end

      run prompt(
            "anthropic:claude-haiku-4-5",
            tools: false,
            prompt: &Manillum.Archive.Cataloging.Prompt.template/2,
            req_llm: Manillum.AI.ReqLLM
          )
    end

    update :mark_cataloging do
      description """
      Visibility-marker transition: `:pending → :cataloging`. Called by
      `RunCataloging` before kicking off the LLM call so concurrent
      observers (and the AshOban scheduler) see a row that is no longer
      `:pending`. Internal — not part of the public Archive interface.
      """

      accept []
      require_atomic? false

      change set_attribute(:status, :cataloging)
    end

    update :catalog do
      description """
      AshOban-driven orchestration: flips the capture's status, calls
      `:extract_drafts`, persists draft Card rows, and broadcasts
      `:cards_drafted` / `:cards_drafting_failed`. See
      `Manillum.Archive.Capture.Changes.RunCataloging` for the
      step-by-step.

      The action accepts no fields directly — all state is derived from
      the capture record and the LLM result. `transaction? false` so the
      LLM HTTP call doesn't hold a Postgres transaction open for ~10s;
      `require_atomic? false` because the change orchestrates multi-
      resource side effects.
      """

      accept []
      require_atomic? false
      transaction? false

      change Manillum.Archive.Capture.Changes.RunCataloging
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :source_text, :string do
      allow_nil? false
      public? true

      description "The chunk of conversation text the user submitted for cataloging."
    end

    attribute :scope, :atom do
      allow_nil? false

      constraints one_of: [:whole, :selection]
      public? true

      description """
      Which save modality produced this capture: `:whole` (full assistant
      message) or `:selection` (a user-highlighted text range).
      """
    end

    attribute :selection_start, :integer, public?: true
    attribute :selection_end, :integer, public?: true

    attribute :status, :atom do
      default :pending
      allow_nil? false
      constraints one_of: [:pending, :cataloging, :catalogued, :failed]
      public? true

      description """
      Lifecycle: `:pending` → `:cataloging` → `:catalogued | :failed`.
      The AshOban scan trigger filters on `:pending`; `RunCataloging`
      moves the row through the other states.
      """
    end

    attribute :error_reason, :string do
      public? true

      description "Populated when status transitions to `:failed`. Free-text reason for the filing tray to surface."
    end

    # The bare UUID columns are kept as attributes (no FK constraint —
    # Capture rows long-outlive deleted conversations as audit trail
    # per spec §5 Stream C). The `belongs_to :conversation` and
    # `belongs_to :message` relationships below reuse these columns
    # via `define_attribute? false` so the filing tray can load
    # provenance (QRY № N · ¶ M) alongside drafts in one query.
    attribute :conversation_id, :uuid, public?: true
    attribute :message_id, :uuid, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Manillum.Accounts.User do
      allow_nil? false
      public? true
    end

    belongs_to :conversation, Manillum.Conversations.Conversation do
      source_attribute :conversation_id
      destination_attribute :id
      public? true
      define_attribute? false
    end

    belongs_to :message, Manillum.Conversations.Message do
      source_attribute :message_id
      destination_attribute :id
      public? true
      define_attribute? false
    end

    has_many :drafts, Manillum.Archive.Card do
      destination_attribute :capture_id
    end
  end
end
