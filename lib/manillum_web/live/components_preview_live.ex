defmodule ManillumWeb.ComponentsPreviewLive do
  @moduledoc """
  Visual preview of every Manillum component in all of its meaningful
  states. Mounted at `/dev/components` (dev-only via `dev_routes`).

  This page is the canonical reference for Gate H.1 visual review and the
  living spec for downstream Streams D / E / F. If a component changes,
  this page is the first place to verify.
  """

  use ManillumWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("demo_flash", %{"kind" => "info"}, socket) do
    {:noreply,
     put_flash(socket, :info, "Catalog still drafting — Livy will surface drafts when ready.")}
  end

  def handle_event("demo_flash", %{"kind" => "ok"}, socket) do
    {:noreply,
     put_flash(socket, :ok, %{
       kicker: "● FILED",
       title: "3 cards filed in Dr. 01 Antiquity",
       body: "From QRY № 0089. Each card is independently scheduled for review."
     })}
  end

  def handle_event("demo_flash", %{"kind" => "warn"}, socket) do
    {:noreply,
     put_flash(socket, :warn, %{
       kicker: "● POSSIBLE DUPLICATE",
       title: "Looks like an existing card",
       body: "Found ANT · 1177BC · COLLAPSE. Review at the filing tray."
     })}
  end

  def handle_event("demo_flash", %{"kind" => "error"}, socket) do
    {:noreply,
     put_flash(socket, :error, %{
       kicker: "● FILING FAILED",
       title: "Slug collision",
       body: "Couldn't save — the call number already exists. Edit the slug to differentiate."
     })}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.topbar
        active="components"
        tagline="— design system preview"
        meta="GATE H.1 · 14 COMPONENTS"
      >
        <:tab id="today" href={~p"/"}>Today</:tab>
        <:tab id="components" href="/dev/components">Components</:tab>
        <:tab id="dashboard" href="/dev/dashboard">Dashboard</:tab>
      </.topbar>
      <.era_band pin_year={1519} pin_label="design system review" />

      <ManillumWeb.Layouts.flash_group flash={@flash} />

      <div class="cpv">
        <header class="cpv__intro">
          <.kicker>● Manillum · stream H · gate H.1</.kicker>
          <h1 class="cpv__title">
            The visual design system, on one page.
          </h1>
          <p class="cpv__lede">
            Linen ground, oxblood ink, Spectral display, Newsreader body. Every
            component below is the production CSS — no demo styling, no
            placeholders. If it looks right here, it looks right in the app.
          </p>
        </header>

        <.cpv_section
          id="palette"
          title="Palette"
          sub="Grounds & ink, then the deep accents, then the bright variants for small markers."
        >
          <h4 class="cpv__h4">Grounds & ink</h4>
          <div class="cpv__swatches">
            <.swatch name="linen" hex="#e8e3d6" var="--color-linen" tone="ink" />
            <.swatch name="linen-deep" hex="#ddd6c2" var="--color-linen-deep" tone="ink" />
            <.swatch name="paper" hex="#f6f1e3" var="--color-paper" tone="ink" />
            <.swatch name="paper-light" hex="#faf6e8" var="--color-paper-light" tone="ink" />
            <.swatch name="ink" hex="#1a1814" var="--color-ink" tone="paper" />
            <.swatch name="ink-soft" hex="#4a463c" var="--color-ink-soft" tone="paper" />
            <.swatch name="ink-faint" hex="#7d7666" var="--color-ink-faint" tone="paper" />
          </div>

          <h4 class="cpv__h4">Deep — for type, drop-caps, large color fields</h4>
          <div class="cpv__swatches">
            <.swatch name="oxblood" hex="#5e1a1a" var="--color-oxblood" tone="paper" />
            <.swatch name="oxblood-soft" hex="#8a3a2c" var="--color-oxblood-soft" tone="paper" />
            <.swatch name="forest" hex="#3a4a2c" var="--color-forest" tone="paper" />
            <.swatch name="brass" hex="#9a7a3a" var="--color-brass" tone="paper" />
          </div>

          <h4 class="cpv__h4">
            Bright — for small visual markers (dots, bullets, thin borders)
          </h4>
          <div class="cpv__swatches">
            <.swatch name="oxblood-bright" hex="#a4332c" var="--color-oxblood-bright" tone="paper" />
            <.swatch name="forest-bright" hex="#6b853f" var="--color-forest-bright" tone="paper" />
            <.swatch name="brass-bright" hex="#b8893a" var="--color-brass-bright" tone="paper" />
          </div>

          <h4 class="cpv__h4">Side-by-side at small sizes — the reason for bright variants</h4>
          <div class="cpv__contrast">
            <div class="cpv__contrast-row">
              <div class="cpv__contrast-label">deep</div>
              <span class="cpv__dot" style="background:var(--color-oxblood)"></span>
              <span class="cpv__dot" style="background:var(--color-oxblood-soft)"></span>
              <span class="cpv__dot" style="background:var(--color-forest)"></span>
              <span class="cpv__dot" style="background:var(--color-brass)"></span>
              <span class="cpv__dot" style="background:var(--color-ink-soft)"></span>
              <div class="cpv__contrast-cap">at 7px the deeps blur into "dark warm thing"</div>
            </div>
            <div class="cpv__contrast-row">
              <div class="cpv__contrast-label">bright</div>
              <span class="cpv__dot" style="background:var(--color-oxblood-bright)"></span>
              <span class="cpv__dot" style="background:var(--color-forest-bright)"></span>
              <span class="cpv__dot" style="background:var(--color-brass-bright)"></span>
              <span class="cpv__dot" style="background:var(--color-ink-soft)"></span>
              <div class="cpv__contrast-cap">brights stay distinct at 7px and 1px</div>
            </div>
          </div>
          <p class="cpv__note">
            Drawers are not colour-coded — the call number's first segment
            (<code>ANT</code> · <code>REN</code> · <code>MID</code>) already
            says which drawer a card belongs to.
          </p>
        </.cpv_section>

        <.cpv_section
          id="type"
          title="Typography"
          sub="Three faces. Spectral · Newsreader · IBM Plex Mono."
        >
          <div class="cpv__typespecs">
            <div class="cpv__typespec">
              <.meta_label>Display · Spectral</.meta_label>
              <div style="font-family:var(--font-display);font-size:3.125rem;line-height:1;letter-spacing:-.012em">
                The day the <em>Renaissance</em> grew old.
              </div>
              <.caption>50px / 500 / italic-em / -1.2% tracking</.caption>
            </div>

            <div class="cpv__typespec">
              <.meta_label>Display · medium</.meta_label>
              <div style="font-family:var(--font-display);font-size:1.625rem;font-weight:500;line-height:1.15">
                File this fact in your drawer
              </div>
              <.caption>26px / 500</.caption>
            </div>

            <div class="cpv__typespec">
              <.meta_label>Body · Newsreader</.meta_label>
              <p style="font-family:var(--font-body);font-size:14px;line-height:1.65;max-width:64ch">
                <.drop_cap>M</.drop_cap>ost historians now treat it as a <em>systems collapse</em>. Between roughly 1200 and 1150 BC,
                nearly every major palace economy in the eastern Mediterranean
                fell within fifty years.
              </p>
              <.caption>14px / 1.65 leading / drop-cap inline</.caption>
            </div>

            <div class="cpv__typespec">
              <.meta_label>Italic · aside</.meta_label>
              <p style="font-family:var(--font-body);font-style:italic;font-size:1rem;color:var(--color-ink-soft)">
                Anything you save lands at <span style="color:var(--color-oxblood);font-style:normal;font-weight:500">~1175 BC</span>.
              </p>
            </div>

            <div class="cpv__typespec">
              <.meta_label>Mono · IBM Plex Mono</.meta_label>
              <div style="font-family:var(--font-mono);font-size:.625rem;letter-spacing:.18em;text-transform:uppercase;color:var(--color-oxblood)">
                ANT · 1200 · OMAR-LEGEND
              </div>
              <.caption>10px / .18em tracking / uppercase</.caption>
            </div>
          </div>
        </.cpv_section>

        <.cpv_section
          id="metadata"
          title="Metadata strips"
          sub="Labels, kickers, captions, QRY stamps."
        >
          <div class="cpv__row">
            <.meta_label>● 247 saved · 14 days</.meta_label>
            <.meta_label tone={:oxblood}>● Antiquity · 12 exchanges · 3 saved</.meta_label>
            <.meta_label tone={:forest}>● Filed today</.meta_label>
            <.meta_label tone={:brass}>● Possible duplicate</.meta_label>
            <.meta_label tone={:ink}>started today · 14:08</.meta_label>
          </div>
          <div class="cpv__row">
            <.kicker>Saturday · 02 May 2026 · on this day</.kicker>
          </div>
          <div class="cpv__row">
            <.qry_stamp>QRY № 0089 · ¶3</.qry_stamp>
            <.qry_stamp>FROM QRY № 0089 · SELECTION</.qry_stamp>
          </div>
          <div class="cpv__row">
            <.caption>The Mouseion site is, today, almost certainly under the harbour.</.caption>
          </div>
        </.cpv_section>

        <.cpv_section
          id="call_number"
          title="Call number"
          sub="The boxed mono identifier — the library-card slug."
        >
          <div class="cpv__row">
            <.call_number>ANT · 1200 · OMAR-LEGEND</.call_number>
            <.call_number tone={:forest}>REN · 1517 · LUTHER-THESES</.call_number>
            <.call_number tone={:brass}>MID · 1066 · HASTINGS</.call_number>
            <.call_number inline>ANT · 1175BC · COLLAPSE</.call_number>
          </div>
        </.cpv_section>

        <.cpv_section
          id="drawer_label"
          title="Drawer label"
          sub="Drawer name with a single accent bullet. Disambiguation is the call number's job, not the colour's."
        >
          <div class="cpv__row">
            <.drawer_label>Dr. 01 · Antiquity</.drawer_label>
            <.drawer_label>Dr. 02 · Classical</.drawer_label>
            <.drawer_label>Dr. 03 · Middle Ages</.drawer_label>
            <.drawer_label>Dr. 04 · Renaissance</.drawer_label>
          </div>
          <div class="cpv__row">
            <.drawer_label>Dr. 05 · Early Modern</.drawer_label>
            <.drawer_label>Dr. 06 · Long 19c.</.drawer_label>
            <.drawer_label>Dr. 07 · Short 20c.</.drawer_label>
            <.drawer_label>Dr. 08 · Now</.drawer_label>
          </div>
          <div class="cpv__row">
            <.drawer_label variant={:display}>
              Antiquity & late antiquity
            </.drawer_label>
            <.drawer_label variant={:strong}>
              ● Reformation
            </.drawer_label>
          </div>
        </.cpv_section>

        <.cpv_section id="stamp" title="Stamp" sub="Square mono badge, ~8° tilt. Sits on card recto.">
          <div class="cpv__row">
            <.stamp>
              FRONT<br />RECTO
            </.stamp>
            <.stamp variant={:upright}>
              BACK<br />VERSO
            </.stamp>
            <.stamp variant={:small}>★</.stamp>
            <.stamp variant={:filled}>FILED</.stamp>
            <span class="stamp stamp--ribbon">F · save it</span>
          </div>
        </.cpv_section>

        <.cpv_section
          id="card"
          title="Card · recto / verso"
          sub="The signature surface. 1° tilt each, opposing directions, oxblood top-rule, gentle drop-shadow."
        >
          <div class="cpv__cards">
            <.card face={:recto}>
              <.card_head>
                <.call_number>ANT · 1200 · OMAR-LEGEND</.call_number>
                <.stamp>
                  FRONT<br />RECTO
                </.stamp>
              </.card_head>
              <.card_question>
                When does the story of Caliph Omar burning the Library of
                Alexandria first appear?
              </.card_question>
              <.card_foot>
                <span>Dr.01 antiquity</span>
                <span>filed 02 may 26</span>
              </.card_foot>
            </.card>

            <.card face={:verso}>
              <.card_head>
                <.call_number tone={:forest}>ANT · 1200 · OMAR-LEGEND</.call_number>
                <.meta_label tone={:forest}>BACK · VERSO</.meta_label>
              </.card_head>
              <.card_answer>
                <.drop_cap>I</.drop_cap>n a 13th-century chronicle by Bar
                Hebraeus — six centuries after the supposed event. No
                contemporaneous Arab or Byzantine source corroborates it.
                Modern historians treat it as legend.
              </.card_answer>
            </.card>
          </div>

          <h4 class="cpv__h4">List variant — used in the timeline grid</h4>
          <div class="cpv__cards-grid">
            <.card face={:list}>
              <.card_head>
                <div class="card__year">−1177</div>
                <div style="text-align:right">
                  <.meta_label>ANTIQUITY</.meta_label>
                  <br />
                  <.meta_label tone={:oxblood}>● Bronze Age</.meta_label>
                </div>
              </.card_head>
              <.card_question>
                Why didn't one cause explain the Bronze Age collapse?
              </.card_question>
              <.card_foot>
                <span>review in 7d</span>
                <span>seen 2×</span>
              </.card_foot>
            </.card>

            <.card face={:list}>
              <.card_head>
                <div class="card__year">−447</div>
                <div style="text-align:right">
                  <.meta_label>CLASSICAL</.meta_label>
                  <br />
                  <.meta_label tone={:oxblood}>● Athens</.meta_label>
                </div>
              </.card_head>
              <.card_question>
                How was the Parthenon actually funded?
              </.card_question>
              <.card_foot>
                <span>review in 4d</span>
                <span>seen 5×</span>
              </.card_foot>
            </.card>

            <.card face={:list}>
              <.card_head>
                <div class="card__year">1066</div>
                <div style="text-align:right">
                  <.meta_label>MID AGES</.meta_label>
                  <br />
                  <.meta_label tone={:brass}>● England</.meta_label>
                </div>
              </.card_head>
              <.card_question>
                Why does Hastings still matter to historians?
              </.card_question>
              <.card_foot>
                <span>review in 21d</span>
                <span>seen 1×</span>
              </.card_foot>
            </.card>

            <.card face={:list}>
              <.card_head>
                <div class="card__year">1517</div>
                <div style="text-align:right">
                  <.meta_label>RENAISSANCE</.meta_label>
                  <br />
                  <.meta_label tone={:brass}>● Reformation</.meta_label>
                </div>
              </.card_head>
              <.card_question>
                Did Luther actually nail the theses to the door?
              </.card_question>
              <.card_foot>
                <span>review in 30d</span>
                <span>seen 1×</span>
              </.card_foot>
            </.card>

            <.card face={:list}>
              <.card_head>
                <div class="card__year">1648</div>
                <div style="text-align:right">
                  <.meta_label>EARLY MOD.</.meta_label>
                  <br />
                  <.meta_label tone={:forest}>● Westphalia</.meta_label>
                </div>
              </.card_head>
              <.card_question>
                What did the Peace of Westphalia really decide?
              </.card_question>
              <.card_foot>
                <span>review in 14d</span>
                <span>seen 3×</span>
              </.card_foot>
            </.card>

            <.card face={:list}>
              <.card_head>
                <div class="card__year">1815</div>
                <div style="text-align:right">
                  <.meta_label>LONG 19C</.meta_label>
                  <br />
                  <.meta_label tone={:forest}>● Vienna</.meta_label>
                </div>
              </.card_head>
              <.card_question>
                What did the Congress of Vienna actually settle?
              </.card_question>
              <.card_foot>
                <span>review in 9d</span>
                <span>seen 2×</span>
              </.card_foot>
            </.card>
          </div>

          <h4 class="cpv__h4">Draft variant — used inside the filing tray</h4>
          <div class="cpv__cards-grid">
            <.card face={:draft}>
              <div style="display:flex;justify-content:space-between;margin-bottom:5px">
                <.call_number inline>ANT · 1175BC · CLINE-FRAME</.call_number>
                <.meta_label>QRY 89 · ¶2</.meta_label>
              </div>
              <.drawer_label>Dr. 01 · Antiquity</.drawer_label>
              <div style="font-family:var(--font-display);font-size:.8125rem;font-weight:500;margin:5px 0;line-height:1.25">
                Whose framing of the collapse is now dominant, and what stresses does it name?
              </div>
              <div style="font-family:var(--font-body);font-size:.78125rem;line-height:1.45;color:var(--color-ink-soft)">
                Eric Cline's: simultaneous drought, earthquake swarms, internal rebellion, and severed trade overwhelmed a fragile interconnected system.
              </div>
              <div style="display:flex;gap:.375rem;padding-top:.375rem;margin-top:.5rem;border-top:1px dotted var(--color-rule)">
                <.action_pill>
                  <.icon name="hero-archive-box-micro" /> file
                </.action_pill>
                <.action_pill variant={:ghost}>edit</.action_pill>
                <.action_pill variant={:bare}>discard</.action_pill>
              </div>
            </.card>
          </div>
        </.cpv_section>

        <.cpv_section
          id="gutter"
          title="Gutter action"
          sub="Marginal filing affordance. Hover anywhere on a paragraph row to reveal the FILE mark."
        >
          <div class="cpv__gutter-frame">
            <.gutter_row index="¶ 1">
              <.drop_cap>M</.drop_cap>ost historians now treat it as a <em>systems collapse</em>. Between roughly 1200 and 1150 BC, nearly every major palace economy in the eastern Mediterranean fell within fifty years.
            </.gutter_row>
            <.gutter_row index="¶ 2" active>
              The Sea Peoples are part of the story but not the whole story. Eric Cline's frame — that
              <em>simultaneous</em>
              stresses overwhelmed a fragile interconnected system — is now the dominant view.
            </.gutter_row>
            <.gutter_row index="¶ 3">
              Of those stresses, drought has the strongest material evidence. Pollen cores from the Sea of Galilee and Cyprus show a roughly three-hundred-year arid phase beginning around 1200 BC.
            </.gutter_row>

            <div style="display:flex;align-items:center;gap:.625rem;margin-top:.5rem;padding-top:.625rem;border-top:1px dotted var(--color-rule);margin-left:3.5rem">
              <.meta_label>3 BLOCKS · 286 WORDS</.meta_label>
              <span style="flex:1"></span>
              <span style="font-family:var(--font-body);font-style:italic;font-size:.78125rem;color:var(--color-ink-faint)">
                trust Livy →
              </span>
              <button class="gutter_action gutter_action--all">
                <.icon name="hero-plus-micro" /> FILE ALL
              </button>
            </div>
          </div>
        </.cpv_section>

        <.cpv_section
          id="filing_tray"
          title="Filing tray"
          sub="Slides in from the right while cataloging is running. Two states."
        >
          <div class="cpv__trays">
            <div class="cpv__tray-frame">
              <h4 class="cpv__h4">Drafting state</h4>
              <.filing_tray
                state={:draft}
                kicker="FILING TRAY"
                title="Drafting cards from QRY № 0089 · ¶2"
                sub="cataloging in the background…"
              >
                <.draft_skeleton prov="QRY 89 · ¶2" />
                <.draft_skeleton prov="QRY 89 · ¶2" />
                <div style="font-family:var(--font-body);font-size:.71875rem;font-style:italic;color:var(--color-ink-faint);text-align:center;padding:.375rem;line-height:1.5">
                  you can keep chatting — tray will surface when ready
                </div>
              </.filing_tray>
            </div>

            <div class="cpv__tray-frame">
              <h4 class="cpv__h4">Review state</h4>
              <.filing_tray
                state={:review}
                kicker="FILING TRAY · 3 DRAFTS"
                title="From QRY № 0089 · file all"
              >
                <:actions>
                  <.action_pill>
                    <.icon name="hero-archive-box-micro" /> file all
                  </.action_pill>
                  <.action_pill variant={:ghost}>review each</.action_pill>
                  <span style="flex:1"></span>
                  <.action_pill variant={:bare}>discard all</.action_pill>
                </:actions>

                <.card face={:draft}>
                  <div style="background:rgba(154,122,58,.14);border:1px solid var(--color-brass);padding:.375rem .5rem;margin-bottom:.5rem;font-family:var(--font-body);font-size:.71875rem;font-style:italic;color:var(--color-ink);line-height:1.4">
                    <.icon name="hero-exclamation-triangle-micro" />
                    Looks like your existing card <.call_number inline tone={:brass}>ANT · 1177BC · COLLAPSE</.call_number>.
                    <div style="display:flex;gap:.375rem;margin-top:.375rem">
                      <span class="action_pill" style="background:var(--color-brass)">merge</span>
                      <.action_pill variant={:ghost}>file as new</.action_pill>
                      <.action_pill variant={:bare}>discard</.action_pill>
                    </div>
                  </div>
                  <div style="display:flex;justify-content:space-between;margin-bottom:5px">
                    <.call_number inline>ANT · 1175BC · SYSTEMS</.call_number>
                    <.meta_label>FROM QRY № 0089 · ¶1</.meta_label>
                  </div>
                  <.drawer_label>
                    Dr. 01 · Antiquity
                  </.drawer_label>
                  <div style="font-family:var(--font-display);font-size:.875rem;font-weight:500;margin:5px 0;line-height:1.25">
                    What does it mean to call the Bronze Age collapse a "systems collapse"?
                  </div>
                </.card>
              </.filing_tray>
            </div>
          </div>
        </.cpv_section>

        <.cpv_section
          id="tags"
          title="Cross-reference tags"
          sub="Coloured with bright variants so the 1px borders register."
        >
          <div class="cpv__row">
            <.tag tint="var(--color-oxblood-bright)" variant={:remove}>Late antiquity</.tag>
            <.tag tint="var(--color-forest-bright)" variant={:remove}>Alexandria</.tag>
            <.tag tint="var(--color-brass-bright)" variant={:remove}>Historiography</.tag>
            <.tag tint="var(--color-ink-soft)" variant={:remove}>Myths</.tag>
            <.tag variant={:add}>+ tag</.tag>
          </div>
          <div class="cpv__row">
            <.tag variant={:small}>Bronze Age</.tag>
            <.tag variant={:small}>Eastern Med.</.tag>
            <.tag variant={:small}>Systems thinking</.tag>
          </div>
        </.cpv_section>

        <.cpv_section
          id="buttons"
          title="Buttons"
          sub="Italic Newsreader, no radius. Three weights of action."
        >
          <div class="cpv__row">
            <.btn>
              <.icon name="hero-archive-box-micro" /> File card
            </.btn>
            <.btn variant={:ghost}>Edit further</.btn>
            <.btn variant={:bare}>discard</.btn>
            <.btn size={:sm}>
              Begin a conversation <.icon name="hero-arrow-right-micro" />
            </.btn>
          </div>
          <div class="cpv__row">
            <.action_pill>
              <.icon name="hero-archive-box-micro" /> file
            </.action_pill>
            <.action_pill variant={:ghost}>edit</.action_pill>
            <.action_pill variant={:bare}>discard</.action_pill>
          </div>
        </.cpv_section>

        <.cpv_section
          id="toasts"
          title="Toasts"
          sub="Manillum's flash / notification — NOT DaisyUI's toast."
        >
          <div class="cpv__toasts">
            <.toast kind={:info} kicker="● NOTICE" title="Catalog still drafting">
              You can keep chatting — Livy will surface drafts when ready.
            </.toast>
            <.toast kind={:ok} kicker="● FILED" title="3 cards filed in Dr. 01 Antiquity">
              From QRY № 0089. Each card is independently scheduled for review.
            </.toast>
            <.toast kind={:warn} kicker="● POSSIBLE DUPLICATE" title="Looks like an existing card">
              Found <.call_number inline tone={:brass}>ANT · 1177BC · COLLAPSE</.call_number>.
              Review at the filing tray.
            </.toast>
            <.toast kind={:error} kicker="● FILING FAILED" title="Slug collision">
              Couldn't save — the call number already exists. Edit the slug to differentiate.
            </.toast>
          </div>

          <h4 class="cpv__h4">Live flash — drives the same toast component</h4>
          <p class="cpv__sub">
            Click any kind to push a flash. Plain strings render as a body-only toast; structured
            payloads carry kicker, title, and body.
          </p>
          <div class="cpv__toasts" style="grid-template-columns:repeat(4,1fr)">
            <.button phx-click="demo_flash" phx-value-kind="info">info · plain</.button>
            <.button phx-click="demo_flash" phx-value-kind="ok">ok · structured</.button>
            <.button phx-click="demo_flash" phx-value-kind="warn">warn · structured</.button>
            <.button phx-click="demo_flash" phx-value-kind="error">error · structured</.button>
          </div>
        </.cpv_section>

        <.cpv_section
          id="era_band"
          title="Era band"
          sub="The persistent timeline chrome at the top of every screen."
        >
          <div class="cpv__era">
            <.era_band pin_year={-1177} pin_label="bronze age collapse" />
          </div>
          <div class="cpv__era">
            <.era_band pin_year={1519} pin_label="leonardo at clos lucé" />
          </div>
          <div class="cpv__era">
            <.era_band pin_year={1914} pin_label="sarajevo" dim />
          </div>
        </.cpv_section>

        <footer class="cpv__foot">
          <.meta_label>● gate H.1 · review checklist</.meta_label>
          <ul class="cpv__checklist">
            <li>Palette: 11 colours render against linen ground</li>
            <li>Typography: Spectral, Newsreader, IBM Plex Mono all loading</li>
            <li>Card: recto/verso tilt is opposing, oxblood top-rule visible</li>
            <li>Call number: oxblood box, .18em tracking, uppercase mono</li>
            <li>Drawer label: bullet-and-name, tint follows drawer</li>
            <li>Stamp: square, ~8° tilt, oxblood-soft (faded)</li>
            <li>Gutter: hover shows + FILE; active state oxblood rule</li>
            <li>Era band: pin lands at correct era for −1177, 1519, 1914</li>
            <li>Tray: drafting (slim) and review (wide) variants</li>
            <li>Toasts: 4 kinds, not DaisyUI</li>
            <li>Buttons: italic, no radius, three weights</li>
          </ul>
        </footer>
      </div>
    </.page>

    <style>
      /* Layout-only utilities for the preview page itself. Lives inline
         so a Stream-D author copying a component doesn't accidentally
         pull preview-only styles. */
      .cpv { padding: 2rem var(--margin-page-x) 4rem; }
      .cpv__intro { max-width: 56ch; margin: 1.5rem 0 3rem; }
      .cpv__title {
        font-family: var(--font-display);
        font-size: var(--text-display-xl);
        font-weight: 500;
        line-height: 1;
        letter-spacing: -.012em;
        margin: .5rem 0 .75rem;
      }
      .cpv__lede {
        font-family: var(--font-body);
        font-style: italic;
        font-size: 1rem;
        color: var(--color-ink-soft);
        line-height: 1.55;
        margin: 0;
      }
      .cpv__section {
        margin-bottom: 3.5rem;
        padding-top: 1.25rem;
        border-top: 1px solid var(--color-rule);
      }
      .cpv__section-head { margin-bottom: 1.25rem; max-width: 56ch; }
      .cpv__section-title {
        font-family: var(--font-display);
        font-size: var(--text-display-md);
        font-weight: 500;
        margin: .25rem 0 .25rem;
        color: var(--color-ink);
      }
      .cpv__section-sub {
        font-family: var(--font-body);
        font-style: italic;
        font-size: .875rem;
        color: var(--color-ink-faint);
        line-height: 1.5;
        margin: 0;
      }
      .cpv__row {
        display: flex;
        align-items: center;
        flex-wrap: wrap;
        gap: 1rem;
        margin-bottom: 1rem;
      }
      .cpv__h4 {
        font-family: var(--font-mono);
        font-size: .625rem;
        letter-spacing: .22em;
        text-transform: uppercase;
        color: var(--color-ink-faint);
        margin: 1.5rem 0 .75rem;
      }
      .cpv__swatches {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
        gap: .5rem;
        margin-bottom: 1rem;
      }
      .cpv__contrast {
        margin-top: .5rem;
        background: var(--color-paper);
        padding: 1rem 1.25rem;
        border-left: 2px solid var(--color-rule-strong);
      }
      .cpv__contrast-row {
        display: flex;
        align-items: center;
        gap: .625rem;
        padding: .375rem 0;
      }
      .cpv__contrast-row + .cpv__contrast-row {
        border-top: 1px dotted var(--color-rule);
      }
      .cpv__contrast-label {
        font-family: var(--font-mono);
        font-size: var(--text-mono-xs);
        letter-spacing: var(--tracking-mono-wide);
        text-transform: uppercase;
        color: var(--color-ink-faint);
        min-width: 11rem;
      }
      .cpv__dot {
        display: inline-block;
        width: 7px;
        height: 7px;
        border-radius: 50%;
        border: 1.5px solid var(--color-linen);
        flex-shrink: 0;
      }
      .cpv__contrast-cap {
        font-family: var(--font-body);
        font-style: italic;
        font-size: .8125rem;
        color: var(--color-ink-faint);
        margin-left: auto;
      }
      .cpv__note {
        font-family: var(--font-body);
        font-style: italic;
        font-size: .8125rem;
        color: var(--color-ink-faint);
        margin: .875rem 0 0;
        line-height: 1.5;
      }
      .cpv__note code {
        font-family: var(--font-mono);
        font-style: normal;
        font-size: .6875rem;
        letter-spacing: .12em;
        color: var(--color-oxblood);
      }
      .cpv__swatch {
        height: 5.5rem;
        padding: .625rem .75rem;
        display: flex;
        flex-direction: column;
        justify-content: space-between;
        border: 1px solid var(--color-rule);
      }
      .cpv__swatch-name {
        font-family: var(--font-mono);
        font-size: .625rem;
        letter-spacing: .14em;
        text-transform: uppercase;
      }
      .cpv__swatch-hex {
        font-family: var(--font-mono);
        font-size: .625rem;
        letter-spacing: .06em;
        opacity: .8;
      }
      .cpv__typespecs {
        display: grid;
        grid-template-columns: 1fr;
        gap: 1.5rem;
      }
      .cpv__typespec {
        padding: 1rem 1.25rem;
        background: var(--color-paper);
        border-left: 2px solid var(--color-rule-strong);
      }
      .cpv__typespec .meta_label { display: block; margin-bottom: .375rem; }
      .cpv__cards {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 22rem));
        gap: 2rem;
        margin-top: 1.25rem;
        padding: 1rem;
      }
      .cpv__cards-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(18rem, 1fr));
        gap: .875rem;
      }
      .cpv__gutter-frame {
        background: var(--color-paper);
        border: 1px solid var(--color-rule);
        padding: 1.25rem;
      }
      .cpv__trays {
        display: grid;
        grid-template-columns: 17rem 26rem;
        gap: 2rem;
        align-items: flex-start;
      }
      .cpv__tray-frame {
        background: var(--color-paper);
        border: 1px solid var(--color-rule);
      }
      .cpv__toasts {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(20rem, 1fr));
        gap: .875rem;
      }
      .cpv__toasts .toast { position: relative; }
      .cpv__era {
        margin-bottom: 1.5rem;
      }
      .cpv__foot {
        margin-top: 2rem;
        padding: 1.5rem;
        background: var(--color-paper);
        border: 1px solid var(--color-rule-strong);
      }
      .cpv__checklist {
        font-family: var(--font-body);
        font-style: italic;
        font-size: .875rem;
        color: var(--color-ink-soft);
        line-height: 1.7;
        margin: .5rem 0 0;
        padding-left: 1.25rem;
      }
    </style>
    """
  end

  # Helper components scoped to this preview only.

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :sub, :string, default: nil
  slot :inner_block, required: true

  defp cpv_section(assigns) do
    ~H"""
    <section id={@id} class="cpv__section">
      <header class="cpv__section-head">
        <.meta_label>● {@id}</.meta_label>
        <h2 class="cpv__section-title">{@title}</h2>
        <p :if={@sub} class="cpv__section-sub">{@sub}</p>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :name, :string, required: true
  attr :hex, :string, required: true
  attr :var, :string, required: true
  attr :tone, :string, default: "ink", values: ~w(ink paper)

  defp swatch(assigns) do
    text_color =
      if assigns.tone == "paper", do: "var(--color-paper-light)", else: "var(--color-ink)"

    assigns = assign(assigns, :text_color, text_color)

    ~H"""
    <div
      class="cpv__swatch"
      style={"background: var(#{@var}); color: #{@text_color}"}
    >
      <div class="cpv__swatch-name">{@name}</div>
      <div class="cpv__swatch-hex">{@hex}</div>
    </div>
    """
  end
end
