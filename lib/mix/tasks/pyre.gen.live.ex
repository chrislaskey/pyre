defmodule Mix.Tasks.Pyre.Gen.Live do
  @moduledoc """
  Generates LiveView files using Igniter.

  Unlike `framework.gen.live`, this task uses Igniter's AST-based code
  generation instead of string replacement templates. It produces properly
  formatted code, supports dry-run previews, and can be composed with
  other Igniter tasks.

  ## Usage

      mix pyre.gen.live AppWeb.PageLive

  ## Examples

      mix pyre.gen.live AccountsWeb.Products
      # => Creates AccountsWeb.ProductsLive.Index (auto-adds Live suffix)

      mix pyre.gen.live Accounts.Example
      # => Creates AccountsWeb.ExamplesLive.Index (auto-pluralized, auto-Web/Live)

      mix pyre.gen.live Accounts.Products.Product
      # => Creates AccountsWeb.ProductsLive.Index (derives from schema name)

  ## Options

    * `--exact` - Use the exact name provided without pluralization
    * `--pubsub` - PubSub module name (default: `Framework.PubSub`)

  This will create:
    - LiveView Index module (e.g., `AccountsWeb.ProductsLive.Index`)
    - LiveView Index Context module (e.g., `AccountsWeb.ProductsLive.Index.Context`)
    - HEEx template (e.g., `index.html.heex`)

  """
  @shortdoc "Generates LiveView files using Igniter"

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      positional: [:module_name],
      schema: [exact: :boolean, pubsub: :string],
      defaults: [exact: false, pubsub: "Framework.PubSub"],
      example: "mix pyre.gen.live AccountsWeb.ProductsLive"
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    module_input = igniter.args.positional.module_name
    pluralize? = !igniter.args.options[:exact]
    pubsub = igniter.args.options[:pubsub]

    {web_module_name, page_name} = parse_module_name(module_input, pluralize?)

    live_module = Module.concat([web_module_name, page_name, "Index"])
    context_module = Module.concat([web_module_name, page_name, "Index", "Context"])

    topic_name =
      page_name
      |> String.replace_suffix("Live", "")
      |> Macro.underscore()

    igniter
    |> create_live_index(live_module, web_module_name, context_module)
    |> create_live_context(context_module, pubsub, topic_name)
    |> create_heex_template(live_module, web_module_name)
  end

  # --- Module Name Parsing ---

  defp parse_module_name(full_module_name, pluralize?) do
    parts = String.split(full_module_name, ".")

    case length(parts) do
      n when n >= 3 ->
        app_name = List.first(parts)
        schema_name = List.last(parts)
        base_name = strip_live_suffix(schema_name)
        base_name = maybe_pluralize(base_name, pluralize?)
        {ensure_web_suffix(app_name), ensure_live_suffix(base_name)}

      2 ->
        [app_part, page_part] = parts
        base_name = strip_live_suffix(page_part)
        base_name = maybe_pluralize(base_name, pluralize?)
        {ensure_web_suffix(app_part), ensure_live_suffix(base_name)}

      1 ->
        [app_part] = parts
        base_name = strip_live_suffix(app_part)
        base_name = maybe_pluralize(base_name, pluralize?)
        {ensure_web_suffix(app_part), ensure_live_suffix(base_name)}
    end
  end

  defp maybe_pluralize(name, true), do: Inflex.pluralize(name)
  defp maybe_pluralize(name, false), do: name

  defp ensure_web_suffix(name) do
    if String.ends_with?(name, "Web"), do: name, else: name <> "Web"
  end

  defp strip_live_suffix(name) do
    if String.ends_with?(name, "Live"),
      do: String.replace_suffix(name, "Live", ""),
      else: name
  end

  defp ensure_live_suffix(name) do
    if String.ends_with?(name, "Live"), do: name, else: name <> "Live"
  end

  # --- Code Generation ---

  defp create_live_index(igniter, live_module, web_module_name, context_module) do
    code = live_index_code(live_module, web_module_name, context_module)
    Igniter.Project.Module.create_module(igniter, live_module, code)
  end

  defp create_live_context(igniter, context_module, pubsub, topic_name) do
    code = live_context_code(context_module, pubsub, topic_name)
    Igniter.Project.Module.create_module(igniter, context_module, code)
  end

  defp create_heex_template(igniter, live_module, web_module_name) do
    heex_path = heex_path_for_module(igniter, live_module)
    content = heex_template_code(web_module_name)
    Igniter.create_new_file(igniter, heex_path, content)
  end

  defp heex_path_for_module(igniter, module) do
    igniter
    |> Igniter.Project.Module.proper_location(module)
    |> String.replace(~r/\.ex$/, ".html.heex")
  end

  # --- Template Code ---

  defp live_index_code(_live_module, web_module_name, context_module) do
    """
    use #{web_module_name}, :live_view

    require Logger

    alias #{inspect(context_module)}, as: Context

    @impl true
    def handle_params(params, _uri, socket) do
      if connected?(socket) do
        Context.pubsub_subscribe(socket)
      end

      {:ok, assigns} = Context.page_data(params, socket)

      {:noreply, assign(socket, assigns)}
    end

    # PubSub

    @impl true
    def handle_info({:page_updated, assigns}, socket) do
      {:noreply, assign(socket, assigns)}
    end

    def handle_info(_event, socket), do: {:noreply, socket}

    # User events

    @impl true
    def handle_event("refresh", params, socket) do
      {:ok, assigns} = Context.page_data(params, socket)

      Context.pubsub_publish(socket, {:page_updated, assigns})

      {:noreply, assign(socket, assigns)}
    end
    """
  end

  defp live_context_code(_context_module, pubsub, topic_name) do
    log_line = ~S'Logger.error("[#{__MODULE__}] Error: #{inspect(error)}")'

    """
    @moduledoc \"\"\"
    Context module for page data and business logic.

    Handles data fetching and processing for the page.
    Separates business logic from the LiveView layer to improve
    testability and maintainability.
    \"\"\"

    require Logger

    # PubSub

    def pubsub_topic(_socket) do
      "#{topic_name}"
    end

    def pubsub_subscribe(socket) do
      Phoenix.PubSub.subscribe(#{pubsub}, pubsub_topic(socket))
    end

    def pubsub_publish(socket, event) do
      Phoenix.PubSub.broadcast(#{pubsub}, pubsub_topic(socket), event)
    end

    # Data

    def page_data(_params \\\\ %{}, _socket) do
      {:ok, page_data} = fetch_page_data()

      {:ok, %{page_data: page_data}}
    end

    # Helpers

    defp fetch_page_data do
      {:ok, DateTime.utc_now()}
    end

    def log_error_then_return(error, value) do
      #{log_line}
      value
    end
    """
  end

  defp heex_template_code(web_module_name) do
    """
    {@page_data}
    <div phx-click="refresh">
      <#{web_module_name}.CoreComponents.icon name="hero-arrow-path" />
    </div>
    """
  end
end
