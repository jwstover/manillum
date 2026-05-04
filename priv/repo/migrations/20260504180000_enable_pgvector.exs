defmodule Manillum.Repo.Migrations.EnablePgvector do
  @moduledoc """
  Enables the `vector` Postgres extension. Required by `Card.embedding`
  (vectorize block, Stream B) and any other resource that needs semantic
  similarity search.
  """

  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS vector")
  end

  def down do
    execute("DROP EXTENSION IF EXISTS vector")
  end
end
