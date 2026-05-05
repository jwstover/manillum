defmodule Manillum.Archive.CardTag do
  @moduledoc """
  Join resource between `Card` and `Tag`. Identity on `(card_id, tag_id)`
  prevents duplicate associations; both sides cascade-delete their join
  rows (a removed Card or Tag drops its associations).

  See spec §4 (CardTag schema) and §5 Stream B task 3.
  """

  use Ash.Resource,
    otp_app: :manillum,
    domain: Manillum.Archive,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "card_tags"
    repo Manillum.Repo

    references do
      reference :card, on_delete: :delete
      reference :tag, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :tag_card do
      description """
      Idempotent association. Repeated calls with the same
      `(card_id, tag_id)` return the existing row instead of erroring.
      """

      accept [:card_id, :tag_id]

      upsert? true
      upsert_identity :unique_card_tag
      upsert_fields []
    end
  end

  attributes do
    uuid_primary_key :id

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :card, Manillum.Archive.Card do
      allow_nil? false
      public? true
    end

    belongs_to :tag, Manillum.Archive.Tag do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_card_tag, [:card_id, :tag_id]
  end
end
