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
