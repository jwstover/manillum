defmodule Manillum.Archive do
  @moduledoc """
  The card archive: filed Cards, their Capture provenance, and (later)
  Tags / Links / CallNumberRedirects.

  See spec §4 for the resource shapes and §7.4 for the call_number format.
  """

  use Ash.Domain, otp_app: :manillum, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Manillum.Archive.Card do
      define :draft_card, action: :draft
      define :file_card, action: :file
      define :propose_call_number, action: :propose_call_number
      define :rename_card, action: :rename
    end

    resource Manillum.Archive.Capture do
      # Public submit entry point — LiveView calls this on `+ FILE` and
      # walks away. The AshOban trigger picks the row up by status and
      # drives the rest. Spec §5 Stream C interface line refers to this
      # as `Manillum.Archive.create!(:submit, %{...})`; the equivalent
      # idiomatic call is `Manillum.Archive.submit!(%{...})`.
      define :submit, action: :submit

      # Sync prompt-backed action exposed for `/notebooks/cataloging.livemd`
      # iteration and for tests. Bypasses Oban + DB entirely.
      define :extract_drafts, action: :extract_drafts, args: [:source_text]
    end

    resource Manillum.Archive.Tag do
      define :find_or_create_tag, action: :find_or_create, args: [:user_id, :name]
    end

    resource Manillum.Archive.CardTag do
      define :tag_card, action: :tag_card, args: [:card_id, :tag_id]
      define :untag_card, action: :destroy
    end

    resource Manillum.Archive.Link do
      define :link, action: :link
      define :unlink, action: :destroy
    end

    resource Manillum.Archive.CallNumberRedirect
  end

  @doc """
  Look up a Card by its call_number string. Parses the format defined in
  spec §7.4 (`[DRAWER] · [DATE] · [SLUG]` with U+00B7 separator) back
  into segments, queries by the `:unique_call_number` identity, and
  falls back to following a `CallNumberRedirect` when no live card is
  present at those segments.

  Multi-rename scenarios resolve naturally: each rename writes a
  redirect from the old segments to the **current** card id, so any
  prior name resolves in a single redirect hop regardless of how many
  times the card has been renamed.

  Returns `{:ok, card}` on success, `{:error, :not_found}` when neither
  a card nor a redirect exists at those segments, or
  `{:error, :invalid_format}` when the input doesn't parse.
  """
  @spec get_card_by_call_number(Ash.UUID.t(), String.t()) ::
          {:ok, Manillum.Archive.Card.t()} | {:error, :not_found | :invalid_format}
  def get_card_by_call_number(user_id, call_number) when is_binary(call_number) do
    case parse_call_number(call_number) do
      {:ok, drawer, date_token, slug} ->
        lookup_card(user_id, drawer, date_token, slug)

      :error ->
        {:error, :invalid_format}
    end
  end

  defp parse_call_number(call_number) do
    case String.split(call_number, " · ", parts: 3) do
      [drawer_str, date_token, slug] ->
        try do
          {:ok, String.to_existing_atom(drawer_str), date_token, slug}
        rescue
          ArgumentError -> :error
        end

      _ ->
        :error
    end
  end

  defp lookup_card(user_id, drawer, date_token, slug) do
    require Ash.Query

    Manillum.Archive.Card
    |> Ash.Query.filter(
      user_id == ^user_id and drawer == ^drawer and date_token == ^date_token and slug == ^slug
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Manillum.Archive.Card{} = card} ->
        {:ok, card}

      {:ok, nil} ->
        follow_redirect(user_id, drawer, date_token, slug)

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Cosine-similarity search over a user's existing cards. Returns the
  ids of filed cards whose `embedding` is within `threshold` cosine
  distance of `query_embedding`, sorted nearest first.

  ## Parameters

  - `user_id` — scope the search to this user's archive.
  - `query_embedding` — a 1536-dim vector (list of floats or
    `Ash.Vector`) produced by `Manillum.AI.Embedding.OpenAI.generate/2`.

  ## Options

  - `:threshold` (default `0.25`) — pgvector cosine distance cutoff.
    `<=>` produces 0 (identical direction) to 2 (opposite). 0.25
    corresponds to ~87% cosine similarity; tighten for more precision,
    loosen for more recall. Tuned during Gate B.3.
  - `:limit` (default `5`) — maximum number of candidates to return.
  - `:exclude_ids` (default `[]`) — card ids to omit (e.g. the draft
    being checked, or candidates the user has already dismissed).
  - `:status` (default `[:filed]`) — which card statuses are eligible
    targets. Cataloging compares against filed cards; reactive linking
    (M-34) will use the same default.

  ## Returns

  A list of `Ash.UUID.t()` ordered by cosine distance ascending
  (nearest first). Cards without an embedding are excluded
  automatically (the embedding job runs async via the
  `:ash_ai_update_embeddings` AshOban trigger; recently-filed cards
  may not yet have one). Empty list when no candidates clear the
  threshold or when `query_embedding` is `nil`.
  """
  @type embedding :: [float()] | Ash.Vector.t()
  @spec find_duplicates(Ash.UUID.t(), embedding() | nil, keyword()) :: [Ash.UUID.t()]
  def find_duplicates(user_id, query_embedding, opts \\ [])

  def find_duplicates(_user_id, nil, _opts), do: []

  def find_duplicates(user_id, query_embedding, opts) when is_binary(user_id) do
    require Ash.Expr
    require Ash.Query
    require Ash.Sort

    threshold = Keyword.get(opts, :threshold, 0.25)
    limit = Keyword.get(opts, :limit, 5)
    exclude_ids = Keyword.get(opts, :exclude_ids, [])
    statuses = Keyword.get(opts, :status, [:filed])

    case to_vector(query_embedding) do
      {:ok, vector} ->
        sort_expr = Ash.Sort.expr_sort(vector_cosine_distance(embedding, ^vector), :float)

        Manillum.Archive.Card
        |> Ash.Query.select([:id])
        |> Ash.Query.filter(user_id == ^user_id and status in ^statuses)
        |> Ash.Query.filter(not is_nil(embedding))
        |> exclude_ids(exclude_ids)
        |> Ash.Query.filter(vector_cosine_distance(embedding, ^vector) <= ^threshold)
        |> Ash.Query.sort([{sort_expr, :asc}])
        |> Ash.Query.limit(limit)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.id)

      :error ->
        []
    end
  end

  defp exclude_ids(query, []), do: query

  defp exclude_ids(query, ids) when is_list(ids) do
    require Ash.Query
    Ash.Query.filter(query, id not in ^ids)
  end

  defp to_vector(%Ash.Vector{} = vector), do: {:ok, vector}

  defp to_vector(list) when is_list(list) do
    case Ash.Vector.new(list) do
      {:ok, vector} -> {:ok, vector}
      {:error, _} -> :error
    end
  end

  defp to_vector(_), do: :error

  @doc """
  Returns the partner card ids for every `:see_also` link touching
  `card_id`. Hides the canonical-ordering detail used by storage —
  callers see a symmetric view regardless of which side of the pair
  the queried card is on.

  See `Manillum.Archive.Link` for why see_also is stored once per pair
  rather than once per direction.
  """
  @spec see_also_partner_ids(Ash.UUID.t()) :: [Ash.UUID.t()]
  def see_also_partner_ids(card_id) when is_binary(card_id) do
    require Ash.Query

    Manillum.Archive.Link
    |> Ash.Query.filter(
      kind == :see_also and (from_card_id == ^card_id or to_card_id == ^card_id)
    )
    |> Ash.read!(authorize?: false)
    |> Enum.map(fn link ->
      if link.from_card_id == card_id, do: link.to_card_id, else: link.from_card_id
    end)
  end

  defp follow_redirect(user_id, drawer, date_token, slug) do
    require Ash.Query

    Manillum.Archive.CallNumberRedirect
    |> Ash.Query.filter(
      user_id == ^user_id and drawer == ^drawer and date_token == ^date_token and slug == ^slug
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Manillum.Archive.CallNumberRedirect{current_card_id: card_id}} ->
        Ash.get(Manillum.Archive.Card, card_id, authorize?: false)

      {:ok, nil} ->
        {:error, :not_found}

      {:error, _} = err ->
        err
    end
  end
end
