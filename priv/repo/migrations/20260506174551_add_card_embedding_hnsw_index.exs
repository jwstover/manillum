defmodule Manillum.Repo.Migrations.AddCardEmbeddingHnswIndex do
  @moduledoc """
  Adds a pgvector HNSW index on `cards.embedding` using the
  `vector_cosine_ops` operator class. Powers
  `Manillum.Archive.find_duplicates/2`'s cosine-similarity lookup over
  filed cards (Slice 6 / M-24).

  Cosine ops are paired with the `<=>` distance operator (range 0..2,
  smaller = more similar). Order-by + LIMIT queries on `embedding <=> ?`
  use this index.

  ## Concurrent build

  Built non-concurrently. At MVP scale (single user, low thousands of
  cards) the build is sub-second and a brief table-write lock is fine.
  At scale, swap to `CREATE INDEX CONCURRENTLY` (which requires
  `@disable_ddl_transaction true` + `@disable_migration_lock true`).
  """

  use Ecto.Migration

  def up do
    execute("""
    CREATE INDEX cards_embedding_hnsw_idx
    ON cards
    USING hnsw (embedding vector_cosine_ops)
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS cards_embedding_hnsw_idx")
  end
end
