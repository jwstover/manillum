defmodule Manillum.Archive.Link do
  @moduledoc """
  A directed edge between two `Card`s in the same user's archive.

  Three kinds (per spec §4):

    * `:see_also` — the soft "you might also be interested in this" link
      surfaced in browse views.
    * `:derived_from` — the from-card cites or builds on the to-card.
    * `:references` — generic citation edge.

  Identity on `(from_card_id, to_card_id, kind)` lets the same pair
  carry distinct edges of different kinds without duplication. Validations
  reject self-links and cross-user edges.

  See spec §4 (Link schema) and §5 Stream B task 4.
  """

  use Ash.Resource,
    otp_app: :manillum,
    domain: Manillum.Archive,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "links"
    repo Manillum.Repo

    references do
      reference :from_card, on_delete: :delete
      reference :to_card, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :link do
      description """
      Create a directed edge between two cards. Idempotent on identity
      `(from_card_id, to_card_id, kind)` — repeating with the same triple
      returns the existing edge.
      """

      accept [:from_card_id, :to_card_id, :kind]

      upsert? true
      upsert_identity :unique_directed_link
      upsert_fields []

      validate Manillum.Archive.Link.Validations.DifferentCards
      validate Manillum.Archive.Link.Validations.SameUser
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      allow_nil? false
      constraints one_of: [:see_also, :derived_from, :references]
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :from_card, Manillum.Archive.Card do
      allow_nil? false
      public? true
    end

    belongs_to :to_card, Manillum.Archive.Card do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_directed_link, [:from_card_id, :to_card_id, :kind]
  end
end
