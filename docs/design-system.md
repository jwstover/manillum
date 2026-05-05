# Manillum design system

Manillum's visual language: linen ground, oxblood ink, Spectral display, Newsreader body, IBM Plex Mono metadata. The aesthetic is *dark academia / library card catalog* — moody, scholarly, restrained, serif-forward, with mono accents.

This doc is the discipline guide for **what goes where**. The components themselves live in `assets/css/components/*.css` and `lib/manillum_web/components/manillum_components.ex`; the live preview is `/dev/components` (dev-only).

---

## The four layers

Manillum's CSS is organized into four cooperating layers. Each layer has a strict job. When you don't know where to put a thing, the rule below picks the layer.

### 1. `assets/css/tokens.css` — design tokens

The single source of truth for the look. Tailwind 4 `@theme` block defining:

- The colour palette: linen / paper / ink (3 grounds, 3 inks), 4 deep accents (oxblood, oxblood-soft, forest, brass) for type and large color fields, 3 bright variants (oxblood-bright, forest-bright, brass-bright) for small visual markers, 3 rules. **No per-drawer colour palette** — the call number's first segment ("ANT", "REN", "MID"…) does the disambiguating, so adding eight drawer-specific hues just adds noise.
- Three font families (Spectral, Newsreader, IBM Plex Mono)
- Display + body + mono type scales
- Tracking + leading
- Manuscript margins (`--margin-page-x`, `--gutter-w`, `--gutter-pad`)
- Card geometry (tilt angles, shadow, top-rule width)
- The DaisyUI bridge (`--color-base-*`, `--color-primary`, etc.) so AshAuth Phoenix UI inherits the linen aesthetic.

**What goes here:** numbers and values. **Never:** styles, layouts, or component rules.

### 2. `assets/css/components/<name>.css` — hand-written component CSS

The distinctive bits. Each file owns one component, and components carry one canonical class — markup uses `<div class="card card--recto">`, not `<div class="bg-paper border border-rule rounded-none rotate-[-1.2deg]…">`.

Current components:

| File | Component | Markup class |
|---|---|---|
| `page.css` | linen-grounded surface, manuscript columns | `.page` |
| `topbar.css` | wordmark + tabs + meta | `.topbar` |
| `era_band.css` | persistent timeline chrome | `.era_band` |
| `card.css` | recto / verso / draft / list / preview | `.card` |
| `call_number.css` | boxed mono identifier | `.call_number` |
| `drawer_label.css` | colour-bullet drawer name | `.drawer_label` |
| `stamp.css` | square mono badge, tilted | `.stamp` |
| `gutter_action.css` | left-margin FILE affordance | `.gutter_action` |
| `drop_cap.css` | oxblood Spectral initial | `.drop_cap` |
| `meta.css` | mono kicker / caption / qry stamp | `.meta_label`, `.kicker`, `.caption`, `.qry_stamp` |
| `filing_tray.css` | right-side cataloging drawer | `.filing_tray` |
| `button.css` | italic Newsreader actions | `.btn-manillum`, `.action_pill` |
| `tag.css` | cross-reference tag | `.tag` |
| `toast.css` | flash / notification | `.toast` |

**What goes here:** anything that's the visual signature of Manillum — cards, drawers, call numbers, stamps, the era band, the filing tray. **Never:** plain layout, generic spacing, generic flexbox.

The `&__element` and `&--variant` BEM-ish convention is followed — e.g. `.card__head`, `.card--recto`, `.card--draft`. Variants are mutually exclusive with the same root.

### 3. Tailwind utilities — used freely for layout

Padding, gap, flex, grid, sizing — anything that's *invisible*. If you find yourself writing `display: flex; gap: .5rem; align-items: center;` in a component CSS file three times in a row, that's Tailwind utility work, not component work.

**Examples:**
- `class="flex items-center gap-4"` — fine, layout-only
- `class="grid grid-cols-3 gap-2"` — fine, layout-only
- `class="bg-oxblood text-paper-light px-4 py-2 italic font-body"` — **not fine**; that's a button. Make it `<.btn>`.

The rule of thumb: **if a string of Tailwind classes describes a *thing*, it should be a component instead. If they just describe its position on the page, leave them as utilities.**

### 4. DaisyUI — opt-in per surface

DaisyUI is wired into Manillum's theme (`@plugin "../vendor/daisyui-theme"` in `app.css`) so the prebuilt AshAuth Phoenix UI for sign-in / register / reset / confirm inherits the linen aesthetic via `--color-base-*` and `--color-primary`.

**Use DaisyUI for:** forms, modals, dropdowns, AshAuth Phoenix UI surfaces, any AshAdmin surface, the LiveDashboard.

**Never use DaisyUI for:** cards, drawers, the filing tray, the chat-to-card flow, the era band, the timeline. Those are Manillum's signature surfaces — DaisyUI's generic chrome would homogenize the look.

**No dark theme.** Manillum is a single, scholarly-light aesthetic by design (parchment, candlelight). The default DaisyUI theme is `manillum`; the previous `light` and `dark` themes are removed.

---

## How a Phoenix template should look

A typical surface — `chat_live.html.heex`, say — will use a mix of all four layers. The mix is *normal*:

```heex
<.page>                                          <!-- layer 2 component -->
  <.topbar active="conversation" meta="247 SAVED · 14 DAYS">
    <:tab id="today" href={~p"/"}>Today</:tab>
    <:tab id="conversation" href={~p"/chat"}>Conversation</:tab>
  </.topbar>
  <.era_band pin_year={-1175} pin_label="bronze age collapse" />

  <div class="grid grid-cols-[1fr_240px] gap-7 p-8">  <!-- layer 3 utilities -->
    <article class="page__column">                    <!-- layer 2 component -->
      <.gutter_row index="¶ 1">
        <.drop_cap>M</.drop_cap>ost historians treat it as a systems collapse…
      </.gutter_row>
    </article>

    <aside>
      <.meta_label>How filing works</.meta_label>      <!-- layer 2 component -->
      <.caption>Hover any paragraph for a margin mark.</.caption>
    </aside>
  </div>

  <.filing_tray state={:draft} title="Drafting cards from QRY № 0089"> <!-- layer 2 -->
    <.draft_skeleton prov="QRY 89 · ¶2" />
  </.filing_tray>
</.page>
```

Notice:

- Custom classes (`.page`, `.topbar`, `.gutter_row`, `.filing_tray`) carry the visual signature.
- Tailwind utilities (`grid`, `grid-cols-[…]`, `gap-7`, `p-8`) handle the page layout.
- Tokens (`--font-display`, `--color-oxblood`) live entirely inside the component CSS — never appear in markup.
- DaisyUI doesn't appear on this screen at all. Forms / modals on *other* screens may use it.

---

## Adding a new component

1. **Sketch the markup first.** What's the smallest set of classes you'd want a Stream-D author to type?
2. **Write the CSS in `assets/css/components/<name>.css`.** Pull tokens from `tokens.css`. Keep it tight — under 100 lines is ideal.
3. **Wrap it in a Phoenix component in `lib/manillum_web/components/manillum_components.ex`.** Declare attrs, slot the inner block, render the markup.
4. **Add it to the preview at `/dev/components`.** Use it in every meaningful state (default, active, disabled, dim, etc.). The preview is the gate: if it's not there, the component doesn't exist.
5. **Import the new CSS in `app.css`** under the component layer block.

---

## Adding a new token

Tokens live in `tokens.css` and are referenced in two places:

- As CSS custom properties (`var(--color-oxblood)`) inside hand-written components.
- As Tailwind utilities (`bg-oxblood`, `text-paper-light`) inside layout markup. Tailwind 4 picks tokens up automatically from the `@theme` block — no JS config needed.

When you find yourself writing the same colour or size value in multiple component files, that's a missing token. Add it to `tokens.css`, then replace the literal values.

---

## Anti-patterns we explicitly reject

| Don't | Do |
|---|---|
| `class="text-[#5e1a1a]"` | `class="text-oxblood"` |
| Use `--color-oxblood` for a 7px timeline dot or 1px tag border | Use `--color-oxblood-bright` (or a `--color-drawer-*` token) for any small visual marker |
| Use `--color-oxblood-bright` for body em / drop-caps | Use the deep `--color-oxblood` for type and large color fields |
| Inline `font-family: "Spectral"…` in HEEx | `class="font-display"` *or* a hand-written component |
| `<div class="border border-2 border-dashed border-amber-700 px-2 py-1 italic text-amber-700 font-body">+ tag</div>` | `<.tag variant={:add}>+ tag</.tag>` |
| Two competing flash / notification systems | One: `<.toast>` |
| Borrowing DaisyUI's `<button class="btn btn-primary">` for the "↳ File card" action | `<.btn>↳ File card</.btn>` |
| Adding a dark theme | (Manillum is single-light by design.) |

---

## File organization at a glance

```
assets/css/
├── app.css                    # entry point; imports tokens + components
├── tokens.css                 # design tokens (palette, type, geometry)
└── components/
    ├── button.css
    ├── call_number.css
    ├── card.css
    ├── drawer_label.css
    ├── drop_cap.css
    ├── era_band.css
    ├── filing_tray.css
    ├── gutter_action.css
    ├── meta.css
    ├── page.css
    ├── stamp.css
    ├── tag.css
    ├── toast.css
    └── topbar.css

lib/manillum_web/
├── components/
│   ├── core_components.ex     # DaisyUI helpers (forms, flash, icons)
│   └── manillum_components.ex # Manillum's distinctive components
└── live/
    └── components_preview_live.ex  # /dev/components — Gate H.1 surface
```

---

## Why this discipline

The 2026-05-05 decision (project index): keep Tailwind 4 + DaisyUI, build distinctiveness on top via tokens + per-component CSS rather than ripping the framework out. This works because:

- Tokens prevent palette drift — there's one place to change a colour.
- Components prevent class-soup — markup stays readable and the visual signature stays consistent.
- Tailwind handles layout — we don't reinvent flex / grid / spacing.
- DaisyUI handles form chrome — we don't reinvent input styling.

The cost of this discipline is ~20 lines of vigilance per surface. The benefit is that Stream D / E / F can move quickly without each author redesigning the look from scratch.
