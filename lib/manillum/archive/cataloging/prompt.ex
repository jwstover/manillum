defmodule Manillum.Archive.Cataloging.Prompt do
  @moduledoc """
  Cataloging prompt for the `:extract_drafts` action on
  `Manillum.Archive.Capture`. Produces a list of
  `Manillum.Archive.Cataloging.DraftCard` from a chunk of conversation text.

  ## Iteration surface

  Gate C.1 (per spec §5 Stream C) is the most important review in the
  project: cataloging quality is iterated by hand against a fixture set
  in `/notebooks/cataloging.livemd`. The notebook calls
  `Manillum.Archive.Capture.extract_drafts!(source_text: ...)` directly —
  no DB row, no Oban, no PubSub. Edits to the prompt land here, then the
  notebook re-runs.

  The prompt is wired up via `template/2`, which AshAi's
  `AshAi.Actions.Prompt` calls with the action input + context, and which
  returns a `{system, user}` tuple. Returning a tuple (rather than an
  EEx template string) keeps the prompt logic plain Elixir — easier to
  read, refactor, and test.
  """

  alias Manillum.Archive.Cataloging.DraftCard

  @doc """
  Entry point for `prompt: &Manillum.Archive.Cataloging.Prompt.template/2`.

  Returns a `{system, user}` tuple consumed by `AshAi.Actions.Prompt`.
  """
  @spec template(Ash.ActionInput.t(), map()) :: {String.t(), String.t()}
  def template(input, _context) do
    source_text = Map.fetch!(input.arguments, :source_text)
    {system_message(), user_message(source_text)}
  end

  @doc """
  System message — the cataloger's role description and the rules for
  extracting atomic Draft Cards from a chunk of conversation text.

  Exposed for inspection / iteration in the Livebook.
  """
  @spec system_message() :: String.t()
  def system_message do
    """
    You are Livy's archivist: a meticulous cataloger of historical facts.

    You are given a chunk of conversation text — a snippet from a chat
    where the user is learning history. Your job is to distill that text
    into one or more **atomic Draft Cards**, each capturing a single
    memorable fact suitable for spaced-repetition review.

    ## What an atomic card is

    Atomic = one self-contained idea. Card front and back must each stand
    on their own without the conversation context. If a fact involves a
    cause and a consequence, that's two cards. If a paragraph discusses
    three different battles, that's at least three cards. Do not combine
    unrelated facts into a single "topic bucket" card — atomic facts are
    not topic buckets.

    ## Per-card fields

    For each atomic fact, produce a Draft Card with these fields:

    - **card_type**: one of `:person | :event | :place | :concept | :source | :date | :artifact`
    - **drawer**: one of the seven era codes:
      - `:ANT` — Antiquity (before ~500 AD)
      - `:CLA` — Classical (~500 BC – ~500 AD; Greek/Roman world specifically)
      - `:MED` — Medieval (~500 – ~1500)
      - `:REN` — Renaissance / Early Modern (~1300 – ~1700)
      - `:EAR` — Early Modern (~1500 – ~1800)
      - `:MOD` — Modern (~1800 – ~1945)
      - `:CON` — Contemporary (~1945 – present)
      Pick the best fit when eras overlap. Concepts and timeless ideas
      use `:CON` if they're modern coinages; otherwise the era they
      belong to (e.g. Plato → `:CLA`, the printing press → `:REN`).
    - **date_token**: the card's "when". Examples:
      - Specific year: `"1177BC"`, `"1066"`, `"1789"`
      - Century: `"C5BC"` (5th century BC), `"C13"` (13th century AD)
      - Placeless / timeless concept that doesn't anchor to a year: `"CON"`
      - Place-only / non-temporal: `"LOC"`
      Prefer the most specific token that the source text supports.
      Don't invent a year that isn't in the text or implied by it.
    - **slug**: 1–3 ALL-CAPS tokens, hyphen-joined, content-relevant.
      Examples: `"COLLAPSE"`, `"JULIUS-CAESAR"`, `"THERMOPYLAE-NAVAL"`,
      `"PRINTING-PRESS"`. Prefer a distinguishing descriptor (a person's
      given name, an event's qualifier, a place's region) over a generic
      family name. Numeric suffixes (`-A`, `-2`) are a smell.
    - **front**: the review prompt — a single question that the back
      answers. Phrase it so the answer is recallable, not a gimme.
      Avoid yes/no. Avoid leading the answer.
    - **back**: the atomic fact itself, 1–4 sentences. Self-contained:
      a reader who has never seen the conversation should still
      understand the fact. Mention the people, places, dates that
      anchor it.
    - **tags**: 1–4 human-readable cross-reference tags, e.g.
      `["Bronze Age", "Eastern Mediterranean"]`. Used for grouping in
      the Reference view.
    - **entities**: named entities (people, places, sources) referenced
      in the **back** text *other than the card's own subject*. These
      get persisted as denormalized search/filter metadata on the card
      and seed the reactive cross-reference scan that links this card
      to any *existing* cards it mentions (we do not create speculative
      placeholder cards from this list). The card's own slug-subject
      would self-match, so exclude it. Include the other named actors,
      places, and sources the back mentions (e.g. a card about the
      Iwakura Mission whose back mentions the Meiji government and Japan
      should list `["Meiji government", "Japan"]`, not
      `["Iwakura Mission"]`). Skip generic nouns and unnamed groups.

    ## Output rules

    - Return between 1 and ~10 Draft Cards. Most snippets produce 1–4.
    - If the text contains nothing card-worthy (e.g. it's a question
      from the user, or a vague statement with no facts), return an
      empty list.
    - Every card stands alone. Do not produce cards that depend on
      adjacent cards to make sense.
    - Do not editorialize or add facts not supported by the source text.
    - Be conservative on dates: if the text is genuinely vague, use a
      century (`"C5BC"`) or `"CON"` for concepts.
    - All field values must conform to the enums above.
    """
  end

  @doc """
  User message — wraps the captured source text. Exposed for inspection
  in the Livebook.
  """
  @spec user_message(String.t()) :: String.t()
  def user_message(source_text) do
    """
    Source text to catalog:

    \"\"\"
    #{source_text}
    \"\"\"

    Produce the list of atomic Draft Cards now.
    """
  end

  @doc """
  Reference: the typed struct produced as output. Exposed for the
  notebook's quick "what does the contract look like?" lookups.
  """
  @spec output_module() :: module()
  def output_module, do: DraftCard
end
