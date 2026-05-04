defmodule Manillum.Archive.Capture do
  @moduledoc """
  Stub for Slice 3 — only the resource declaration, so `Card.belongs_to
  :capture` compiles. The full Capture schema (status enum, source-context
  fields, `:submit` / `:extract_drafts` / `:catalog` actions, AshOban scan
  trigger) lands in Slice 4 (Stream C, the cataloging pipeline). See spec
  §4 and §5 Stream C for the eventual shape.
  """

  use Ash.Resource,
    otp_app: :manillum,
    domain: Manillum.Archive,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "captures"
    repo Manillum.Repo
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
