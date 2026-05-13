defmodule ManillumWeb.CardHelpers do
  @moduledoc """
  View-side helpers shared between the filing tray and the full-screen
  card editor. Anything LV-facing that touches Card-specific
  formatting / parsing lives here rather than being duplicated across
  `FilingTrayComponent` and `FileCardLive`.
  """

  @doc """
  Render a drawer atom as its full human label (e.g. `:ANT` →
  `"Dr. 01 · Antiquity"`). Drawer keys mirror spec §7.4. Unknown
  atoms render as their string form so the caller doesn't crash on a
  legacy / future drawer value.
  """
  @spec drawer_name(atom() | String.t()) :: String.t()
  def drawer_name(:ANT), do: "Dr. 01 · Antiquity"
  def drawer_name(:CLA), do: "Dr. 02 · Classical"
  def drawer_name(:MED), do: "Dr. 03 · Medieval"
  def drawer_name(:REN), do: "Dr. 04 · Renaissance"
  def drawer_name(:EAR), do: "Dr. 05 · Early Modern"
  def drawer_name(:MOD), do: "Dr. 06 · Modern"
  def drawer_name(:CON), do: "Dr. 07 · Contemporary"
  def drawer_name(other), do: to_string(other)

  @doc """
  The seven drawer codes, in canonical chronological order. Mirrors
  spec §7.4 and `Card.drawer` constraint.
  """
  @spec drawers() :: [atom()]
  def drawers, do: [:ANT, :CLA, :MED, :REN, :EAR, :MOD, :CON]

  @doc """
  Era range tuple `{from_year, to_year}` for a drawer atom. Rough
  boundaries mirroring `ManillumWeb.ManillumComponents.eras/0`; used
  to sort date_tokens like "C5BC" / "LOC" into a drawer-anchored
  position when no explicit year is present.
  """
  @spec drawer_era(atom()) :: {integer(), integer()}
  def drawer_era(:ANT), do: {-3000, -500}
  def drawer_era(:CLA), do: {-500, 500}
  def drawer_era(:MED), do: {500, 1400}
  def drawer_era(:REN), do: {1400, 1650}
  def drawer_era(:EAR), do: {1650, 1800}
  def drawer_era(:MOD), do: {1800, 1991}
  def drawer_era(:CON), do: {1991, 2100}
  def drawer_era(_), do: {0, 0}

  @doc """
  Parse a `date_token` string into a sortable integer year. Mirrors
  the spec §7.4 examples:

      "1177BC"  → -1177
      "1066"    →  1066
      "1789"    →  1789
      "C5BC"    →  -450   (mid-5th-century BC)
      "C13"     →  1250   (mid-13th-century AD)
      "LOC"     →   nil   (timeless — placeless)
      "CON"     →   nil   (timeless concept)

  Returns `nil` when the token is timeless or unparseable; callers
  fall back to the drawer era's midpoint for chronological sort.
  """
  @spec parse_date_token_year(String.t() | nil) :: integer() | nil
  def parse_date_token_year(nil), do: nil
  def parse_date_token_year("LOC"), do: nil
  def parse_date_token_year("CON"), do: nil

  def parse_date_token_year(token) when is_binary(token) do
    cond do
      # "C5BC" / "C12BC" — century BC, return midpoint
      matches = Regex.run(~r/^C(\d+)BC$/i, token) ->
        [_, c] = matches
        n = String.to_integer(c)
        -((n - 1) * 100 + 50)

      # "C13" / "C5" — century AD, midpoint
      matches = Regex.run(~r/^C(\d+)$/i, token) ->
        [_, c] = matches
        n = String.to_integer(c)
        (n - 1) * 100 + 50

      # "1177BC" — explicit BC year
      matches = Regex.run(~r/^(\d+)BC$/i, token) ->
        [_, y] = matches
        -String.to_integer(y)

      # "1066" / "1789" — plain AD year
      matches = Regex.run(~r/^(\d+)$/, token) ->
        [_, y] = matches
        String.to_integer(y)

      true ->
        nil
    end
  end

  def parse_date_token_year(_), do: nil

  @doc """
  Sort key for chronological card listing. Returns the parsed year
  from `date_token`, falling back to the midpoint of `drawer`'s era
  when the token is timeless (LOC / CON) or unparseable. Guarantees
  an integer for comparison.
  """
  @spec date_sort_key(map()) :: integer()
  def date_sort_key(%{date_token: token, drawer: drawer}) do
    case parse_date_token_year(token) do
      nil ->
        {from, to} = drawer_era(drawer)
        div(from + to, 2)

      year ->
        year
    end
  end

  @doc """
  Convert a drawer string ("ANT" / "CLA" / …) into the matching atom.
  Returns `nil` for blank / unknown values so the caller can decide
  whether to fall back to the row's existing drawer or surface an
  error. Safe even when the atom hasn't been loaded yet — guarded by
  `String.to_existing_atom`.
  """
  @spec atomize_drawer(any()) :: atom() | nil
  def atomize_drawer(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  def atomize_drawer(_), do: nil

  @doc """
  Render an `%Ash.Error.Invalid{}` as a single-line human-readable
  message. Joins each error's `:message` with `"; "` and falls back to
  inspect-rendering when no message is present.
  """
  @spec format_invalid(Ash.Error.Invalid.t()) :: String.t()
  def format_invalid(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.map_join("; ", fn
      %{message: msg} when is_binary(msg) -> msg
      err -> inspect(err)
    end)
    |> case do
      "" -> "Couldn't save."
      msg -> msg
    end
  end
end
