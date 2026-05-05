defmodule Manillum.Archive.Cataloging do
  @moduledoc """
  Namespace for the cataloging pipeline modules — the LLM-driven flow that
  turns a `Manillum.Archive.Capture` (chunk of conversation text + provenance)
  into one or more draft `Manillum.Archive.Card` rows.

  Sub-modules:

    * `Manillum.Archive.Cataloging.DraftCard` — typed struct mirroring §7.1
      of the spec; the return type of `Capture.extract_drafts`.
    * `Manillum.Archive.Cataloging.Prompt` — system + user prompt template
      iterated against Gate C.1 fixtures in `/notebooks/cataloging.livemd`.

  See spec §5 Stream C and §7.1 for the contracts.
  """
end
