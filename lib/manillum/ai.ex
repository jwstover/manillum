defmodule Manillum.AI do
  @moduledoc """
  Ash domain housing prompt-backed actions and the OpenAI embedding model
  implementation. The "AI boundary" for the rest of the app: no other module
  calls Anthropic or OpenAI directly.

  > #### Note on the spec {: .info}
  >
  > Spec §4 originally describes `Manillum.AI` as "a thin module namespace (not
  > its own Ash domain)". With the AshAI-native amendment (2026-05-04),
  > prompt-backed actions live on Ash resources, which need to be hosted in an
  > Ash domain. Making `Manillum.AI` itself the domain keeps the namespace flat
  > and matches what the spec actually wants in §5 Stream A/C. Flagged for
  > reviewer at Gate A.2.
  """
  use Ash.Domain, otp_app: :manillum

  resources do
    resource Manillum.AI.SmokeTest
  end
end
