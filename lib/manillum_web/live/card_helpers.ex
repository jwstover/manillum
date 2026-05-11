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
