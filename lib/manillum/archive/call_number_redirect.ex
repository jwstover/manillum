defmodule Manillum.Archive.CallNumberRedirect do
  @moduledoc """
  A historical call-number → current Card pointer. Written by
  `Card.:rename` when a card's segments change so the old call_number
  remains resolvable via `Manillum.Archive.get_card_by_call_number/2`.

  Identity on `(user_id, drawer, date_token, slug)` ensures at most one
  redirect per old call_number per user. The `:record` action upserts —
  if a card later moves *into* a previously-vacated slug and is itself
  renamed away, the redirect for those segments is updated to point at
  the most-recently-departed card. (The previously-pointed-to card is
  still findable via its current segments, so no information is lost.)

  See spec §4 + §7.4 (rename + redirect contract) and §5 Stream B task 7.
  """

  use Ash.Resource,
    otp_app: :manillum,
    domain: Manillum.Archive,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "call_number_redirects"
    repo Manillum.Repo

    references do
      reference :user, on_delete: :delete
      reference :current_card, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      description """
      Idempotent upsert keyed on the old `(user_id, drawer, date_token,
      slug)` segments. On conflict, updates `current_card_id` so the
      redirect always points at the most-recently-departed card.
      """

      accept [:user_id, :drawer, :date_token, :slug, :current_card_id]

      upsert? true
      upsert_identity :unique_old_call_number
      upsert_fields [:current_card_id, :updated_at]
    end
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

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Manillum.Accounts.User do
      allow_nil? false
      public? true
    end

    belongs_to :current_card, Manillum.Archive.Card do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_old_call_number, [:user_id, :drawer, :date_token, :slug]
  end
end
