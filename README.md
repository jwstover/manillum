# Manillum

A history-learning app: chat with **Livy** (an LLM companion) and save atomic
facts as cards in a personal archive organized like a library card catalog.

See [`AGENTS.md`](AGENTS.md) for working culture and review-gate conventions.

## Local development

### Prerequisites

- Elixir + Erlang (matching `mix.exs`)
- Docker (Postgres runs in a container)
- API keys for Anthropic and OpenAI (see below)

### Environment variables

`req_llm` auto-loads `.env` from the project root via `dotenvy` at startup.
Either drop a `.env` file in place, or export the vars in your shell.

| Variable | Used for | Required for |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | Claude API (Livy + cataloging) | dev, test (smoke), prod |
| `OPENAI_API_KEY` | `text-embedding-3-small` for card vectorization | dev, test (smoke), prod |
| `DATABASE_URL` | Prod Postgres URL | prod release only |
| `SECRET_KEY_BASE` | Phoenix cookie/session signing | prod release only |
| `TOKEN_SIGNING_SECRET` | Ash Authentication tokens | prod release only |

In the test suite, prompt-backed actions are routed through
`Manillum.AI.ReqLLMStub` (configured in `config/test.exs`), so tests do not
hit live APIs and `ANTHROPIC_API_KEY` is not required to run `mix test`.

### Boot

```bash
docker compose up -d postgres   # Postgres on host port 5440
mix setup                       # deps, ash setup, assets
iex -S mix phx.server           # Phoenix on http://localhost:4040
```

### Verifying the AI integration (Gate A.2)

```elixir
# Anthropic prompt-action smoke test
iex> Manillum.AI.SmokeTest.echo("hello world")
{:ok, "Acknowledged: I received the text \"hello world\"."}

# OpenAI embedding model
iex> {:ok, [vector]} = Manillum.AI.Embedding.OpenAI.generate(["test"], [])
iex> length(vector)
1536
```

### Approximate per-call cost

Pricing is in USD per 1M tokens (snapshot from `llm_db`, 2026-05-04):

| Call | Model | Tokens (typical) | Cost |
| --- | --- | --- | --- |
| Smoke `echo` | `claude-haiku-4-5` ($1 in / $5 out) | ~80 in / ~30 out | ~$0.0003 |
| Cataloging | `claude-haiku-4-5` ($1 in / $5 out) | ~1k in / ~500 out | ~$0.0035 |
| Card embedding | `text-embedding-3-small` ($0.02 in) | ~300 in | ~$0.000006 |

These are order-of-magnitude figures; actual usage varies with prompt length
and conversation context. Real billing comes from the provider dashboards.

## Local development ports

| Service | Host port |
| --- | --- |
| Postgres (docker) | 5440 |
| Phoenix dev | 4040 |
| Phoenix test | 4042 |

## Learn more

- Phoenix: https://www.phoenixframework.org/
- Ash Framework: https://hexdocs.pm/ash/
- AshAI: https://hexdocs.pm/ash_ai/
- ReqLLM: https://hexdocs.pm/req_llm/
