defmodule Manillum.Archive.Tag do
  @moduledoc """
  A user-defined label attached to one or more Cards via the `CardTag`
  join. Tags are scoped per-user — two users can independently have a
  `"Bronze Age"` tag without collision.

  Identity on `(user_id, normalized_name)` makes find-or-create
  case-insensitive: `"Bronze Age"`, `"bronze age"`, and `"BRONZE AGE"`
  collapse to a single row, with the **first call's casing** preserved
  in `name`. The `normalized_name` column is the downcased `name` and is
  the column the unique index covers.

  See spec §4 (Tag schema) and §5 Stream B task 3.
  """

  use Ash.Resource,
    otp_app: :manillum,
    domain: Manillum.Archive,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "tags"
    repo Manillum.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :find_or_create do
      description """
      Idempotent upsert keyed on `(user_id, normalized_name)`. Returns
      the existing row when the casing-insensitive name is already
      present for the user; creates a new tag preserving the supplied
      casing otherwise.
      """

      accept [:user_id, :name]

      upsert? true
      upsert_identity :unique_normalized_name
      # Empty list = ON CONFLICT DO NOTHING (returning the existing row).
      # We deliberately preserve the first call's casing on `name` rather
      # than overwriting with whatever casing the second caller passed.
      upsert_fields []

      change Manillum.Archive.Tag.Changes.NormalizeTagName
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true

      description "User-supplied tag label. Casing preserved as first written."
    end

    attribute :normalized_name, :string do
      allow_nil? false
      public? true

      description "Downcased copy of `name`. Drives the case-insensitive unique identity."
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Manillum.Accounts.User do
      allow_nil? false
      public? true
    end

    many_to_many :cards, Manillum.Archive.Card do
      through Manillum.Archive.CardTag
      source_attribute_on_join_resource :tag_id
      destination_attribute_on_join_resource :card_id
    end
  end

  identities do
    identity :unique_normalized_name, [:user_id, :normalized_name]
  end
end
