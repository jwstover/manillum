defmodule ManillumWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: ManillumWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices using Manillum's `.toast` design.

  Flash values may be either a plain string (rendered as the body) or a map
  carrying any of `:title`, `:body`, `:kicker`. The toast variant follows the
  flash key (`:info | :ok | :warn | :error`) unless the `kind` attribute or
  the value's `:kind` overrides it.

  ## Examples

      # plain string — kind comes from the flash key
      put_flash(socket, :info, "Welcome back")

      # structured — title + body + custom kicker
      put_flash(socket, :ok, %{
        kicker: "● FILED",
        title: "3 cards filed in Dr. 01 Antiquity",
        body: "From QRY № 0089. Each card is independently scheduled for review."
      })

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} title="Welcome back" phx-mounted={show("#flash")}>Glad to see you</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kicker, :string, default: nil

  attr :kind, :atom,
    values: [:info, :ok, :warn, :error],
    doc: "used for styling and flash lookup"

  attr :auto_dismiss_ms, :integer,
    default: 10_000,
    doc: "auto-clear the flash after N milliseconds; pass 0 or nil to disable"

  attr :show_progress, :boolean,
    default: false,
    doc: "render a thin progress rule that shrinks across `auto_dismiss_ms`"

  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  slot :actions,
    doc:
      "buttons rendered alongside the body (e.g. an `undo` action). Clicks on actions are NOT swallowed by the flash; only the × button dismisses."

  def flash(assigns) do
    payload = decode_flash(Phoenix.Flash.get(assigns.flash, assigns.kind))

    resolved_kind = (payload && payload[:kind]) || assigns.kind

    resolved_kicker =
      (payload && payload[:kicker]) || assigns.kicker || flash_kicker(resolved_kind)

    auto_ms = assigns.auto_dismiss_ms

    assigns =
      assigns
      |> assign_new(:id, fn -> "flash-#{assigns.kind}" end)
      |> assign(:payload, payload)
      |> assign(:resolved_kind, resolved_kind)
      |> assign(:resolved_kicker, resolved_kicker)
      |> assign(:resolved_title, (payload && payload[:title]) || assigns.title)
      |> assign(:flash_body, payload && payload[:body])
      |> assign(:auto_ms, auto_ms || 0)

    ~H"""
    <div
      :if={@payload || @inner_block != []}
      id={@id}
      role="alert"
      class={["toast", "toast--#{@resolved_kind}"]}
      phx-hook=".FlashAutoDismiss"
      data-dismiss-key={@kind}
      data-dismiss-after={@auto_ms}
      {@rest}
    >
      <div :if={@resolved_kicker} class="toast__kicker">{@resolved_kicker}</div>
      <div :if={@resolved_title} class="toast__title">{@resolved_title}</div>
      <div :if={@flash_body || @inner_block != []} class="toast__body">
        <%= if @flash_body do %>
          {@flash_body}
        <% else %>
          {render_slot(@inner_block)}
        <% end %>
      </div>
      <div :if={@actions != []} class="toast__actions">
        {render_slot(@actions)}
      </div>
      <button
        type="button"
        class="toast__close"
        aria-label={gettext("close")}
        phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      >
        ×
      </button>
      <span
        :if={@show_progress && @auto_ms > 0}
        class="toast__progress"
        style={"animation-duration: #{@auto_ms}ms"}
        aria-hidden="true"
      >
      </span>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".FlashAutoDismiss">
        // Auto-dismiss the flash after `data-dismiss-after` ms by pushing
        // `lv:clear-flash` with the kind. Reads the timeout from a data
        // attribute so callers can pass any duration (or 0 to disable).
        // Cancels on element teardown so a navigation away doesn't push
        // a stale event into the next LV. Pause-on-hover keeps a flash
        // open while the user reads/considers an action button.
        export default {
          mounted() {
            const ms = parseInt(this.el.dataset.dismissAfter || "0", 10);
            if (!ms || ms <= 0) return;

            this.kind = this.el.dataset.dismissKey;
            this.remaining = ms;
            this.start = null;
            this.scheduleHide();

            this.onEnter = () => this.pause();
            this.onLeave = () => this.resume();
            this.el.addEventListener("mouseenter", this.onEnter);
            this.el.addEventListener("mouseleave", this.onLeave);
            this.el.addEventListener("focusin", this.onEnter);
            this.el.addEventListener("focusout", this.onLeave);
          },

          scheduleHide() {
            this.start = performance.now();
            this.timer = setTimeout(() => {
              this.pushEvent("lv:clear-flash", { key: this.kind });
              this.el.style.display = "none";
            }, this.remaining);
          },

          pause() {
            if (!this.timer) return;
            clearTimeout(this.timer);
            this.timer = null;
            const elapsed = performance.now() - this.start;
            this.remaining = Math.max(0, this.remaining - elapsed);
          },

          resume() {
            if (this.timer) return;
            if (this.remaining <= 0) return;
            this.scheduleHide();
          },

          destroyed() {
            if (this.timer) clearTimeout(this.timer);
            if (this.onEnter) {
              this.el.removeEventListener("mouseenter", this.onEnter);
              this.el.removeEventListener("mouseleave", this.onLeave);
              this.el.removeEventListener("focusin", this.onEnter);
              this.el.removeEventListener("focusout", this.onLeave);
            }
          }
        };
      </script>
    </div>
    """
  end

  defp decode_flash(nil), do: nil
  defp decode_flash(""), do: nil
  defp decode_flash(text) when is_binary(text), do: %{body: text}

  defp decode_flash(%{} = map) do
    %{
      kind: map[:kind] || map["kind"],
      title: map[:title] || map["title"],
      body: map[:body] || map["body"] || map[:message] || map["message"],
      kicker: map[:kicker] || map["kicker"]
    }
  end

  defp flash_kicker(:info), do: "● NOTICE"
  defp flash_kicker(:ok), do: "● FILED"
  defp flash_kicker(:warn), do: "● NOTICE"
  defp flash_kicker(:error), do: "● ERROR"
  defp flash_kicker(_), do: nil

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(ManillumWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(ManillumWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
