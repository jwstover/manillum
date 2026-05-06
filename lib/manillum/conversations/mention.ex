defmodule Manillum.Conversations.Mention do
  @moduledoc """
  A historical event surfaced by Livy during a chat. Each mention pins a
  marker on the era band timeline (`ManillumWeb.ManillumComponents.era_band/1`)
  at the position computed by `era_x(year)`.

  Two write paths populate this table:

    * **Tool path (Slice 1)** — Livy calls the `place_event_on_timeline`
      tool mid-response when the conversation establishes a specific dated
      historical event. Immediate, intentional placement.
    * **Sweep path (future slice)** — a conversation-level AshOban scan
      trigger backfills mentions Livy didn't tool-call. Per the
      2026-05-06 vault decision, gated by a two-signal calculation
      (`count(unextracted) >= 3 OR max(unextracted_at) < ago(2, :minute)`).

  Both paths converge on the same identity for find-or-create dedup:
  `(user_id, conversation_id, year, normalized_title)`.

  ## Mention is not Card

  Mention = soft ambient signal "we discussed this." Card = filed atomic
  fact in the archive. When the user later files a card from chat (M-28's
  `+ FILE`), `Card.capture_id` already links provenance back to the source
  message; an optional `Card.mention_id` link can be added later.

  ## Year semantics

  `year` is a signed integer. Negative values are BC: `-44` = 44 BC,
  `-3000` = 3000 BC. We deliberately don't use `Date` because Elixir's
  `Date` rejects BC years and we need to plot Hannibal-era events on the
  band. `month` and `day` are optional — Livy emits only as much precision
  as she's confident in.
  """

  use Ash.Resource,
    otp_app: :manillum,
    domain: Manillum.Conversations,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "mentions"
    repo Manillum.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description """
      Internal create action used by tests and the `:place_event_on_timeline`
      tool action (which adds upsert semantics on top of this).
      """

      accept [:title, :summary, :year, :month, :day]

      argument :conversation_id, :uuid do
        allow_nil? false
        public? false
      end

      argument :message_id, :uuid do
        allow_nil? false
        public? false
      end

      change set_attribute(:conversation_id, arg(:conversation_id))
      change set_attribute(:message_id, arg(:message_id))
      change relate_actor(:user)
      change Manillum.Conversations.Mention.Changes.SetNormalizedTitle
      change Manillum.Conversations.Mention.Changes.SetMentionedAt
    end

    create :place_event_on_timeline do
      description """
      LLM-callable tool action. Livy invokes this from inside `AshAi.ToolLoop.stream`
      whenever the conversation establishes a specific dated historical event.

      Conversation and source-message context come from the action's context
      map (set by `Manillum.Conversations.Message.Changes.Respond` before
      starting the tool loop) — not from the LLM. The LLM only supplies the
      historical-fact fields (`title`, `year`, optional `month` / `day`,
      `summary`). BC years use negative integers (44 BC = `-44`).

      Idempotent on the `(user, conversation, year, normalized_title)`
      identity — repeated tool calls in the same turn (or future-sweep
      backfills of mentions Livy already placed) return the existing row
      without erroring or duplicating.
      """

      upsert? true
      upsert_identity :unique_per_conversation_year_title
      upsert_fields []

      accept [:title, :summary, :year, :month, :day]

      change relate_actor(:user)
      change Manillum.Conversations.Mention.Changes.SetConversationFromContext
      change Manillum.Conversations.Mention.Changes.SetNormalizedTitle
      change Manillum.Conversations.Mention.Changes.SetMentionedAt
    end

    read :for_conversation do
      description """
      List a conversation's mentions in chronological order. Used by
      `ConversationsLive` to populate the era band on initial render.
      """

      argument :conversation_id, :uuid, allow_nil?: false

      prepare build(default_sort: [year: :asc, month: :asc, day: :asc, mentioned_at: :asc])

      filter expr(conversation_id == ^arg(:conversation_id) and user_id == ^actor(:id))
    end
  end

  pub_sub do
    module ManillumWeb.Endpoint
    prefix "chat"

    publish_all :create, ["messages", :conversation_id] do
      transform fn %{data: mention} ->
        %{
          kind: :mention_placed,
          id: mention.id,
          title: mention.title,
          summary: mention.summary,
          year: mention.year,
          month: mention.month,
          day: mention.day,
          message_id: mention.message_id,
          mentioned_at: mention.mentioned_at
        }
      end
    end
  end

  validations do
    validate compare(:month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12) do
      where present(:month)
      message "must be between 1 and 12"
    end

    validate compare(:day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31) do
      where present(:day)
      message "must be between 1 and 31"
    end

    validate present(:month) do
      where present(:day)
      message "is required when day is present"
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      description "Short event name shown in the era band tooltip (\"Battle of Hastings\")."
    end

    attribute :normalized_title, :string do
      allow_nil? false
      public? false

      description """
      Lowercased + trimmed `title`, used in the dedup identity. Set by
      `Mention.Changes.SetNormalizedTitle` on create. Not user-facing.
      """
    end

    attribute :summary, :string do
      public? true
      description "One-line context shown in the era band tooltip."
    end

    attribute :year, :integer do
      allow_nil? false
      public? true

      description """
      Signed year. Negative values are BC (`-44` = 44 BC). Drives timeline
      placement via `era_x/1`.
      """
    end

    attribute :month, :integer do
      public? true
      description "1..12, optional. Validated when present."
    end

    attribute :day, :integer do
      public? true

      description """
      1..31, optional. Day-without-month is rejected because it's
      meaningless for display.
      """
    end

    attribute :mentioned_at, :utc_datetime do
      allow_nil? false
      public? true

      description """
      Timestamp when the mention was placed. Defaults to `DateTime.utc_now/0`
      via `Mention.Changes.SetMentionedAt`. Used for stable ordering when
      multiple mentions share the same `(year, month, day)`.
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

    belongs_to :conversation, Manillum.Conversations.Conversation do
      allow_nil? false
      public? true
    end

    belongs_to :message, Manillum.Conversations.Message do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_per_conversation_year_title,
             [:user_id, :conversation_id, :year, :normalized_title]
  end
end
