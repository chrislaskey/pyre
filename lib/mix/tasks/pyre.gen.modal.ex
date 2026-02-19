defmodule Mix.Tasks.Pyre.Gen.Modal do
  @moduledoc """
  Adds a modal to an existing LiveView using Igniter.

  This task demonstrates Igniter's ability to modify multiple existing files
  in a coordinated way. It adds modal event handlers to a LiveView module,
  modal state initialization to the LiveView context, and modal markup to the
  HEEx template.

  ## Usage

      mix pyre.gen.modal LiveModule modal_name

  ## Examples

      mix pyre.gen.modal ExampleWeb.ProductsLive confirm_delete
      # => Adds confirm_delete modal to ExampleWeb.ProductsLive.Index

  This will modify:
    - LiveView Index module: adds `handle_event` for open/close modal
    - LiveView Context module: adds modal state to `page_data`
    - HEEx template: appends `<.modal>` markup

  ## Options

    * `--title` - Modal title (default: derived from modal name)

  """
  @shortdoc "Adds a modal to an existing LiveView"

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      positional: [:live_module, :modal_name],
      schema: [title: :string],
      defaults: [],
      example: "mix pyre.gen.modal ExampleWeb.ProductsLive confirm_delete"
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    live_input = igniter.args.positional.live_module
    modal_name = igniter.args.positional.modal_name

    live_base = Module.concat(String.split(live_input, "."))
    live_module = Module.concat([live_base, "Index"])
    context_module = Module.concat([live_base, "Index", "Context"])

    modal_title =
      igniter.args.options[:title] ||
        modal_name
        |> String.replace("_", " ")
        |> String.split(" ")
        |> Enum.map_join(" ", &String.capitalize/1)

    assign_key = :"show_#{modal_name}_modal"
    open_event = "open_#{modal_name}_modal"
    close_event = "close_#{modal_name}_modal"

    igniter
    |> add_modal_events(live_module, assign_key, open_event, close_event)
    |> add_modal_state(context_module, assign_key)
    |> add_modal_template(live_module, modal_name, modal_title, assign_key, close_event)
  end

  # --- LiveView Index: Add handle_event callbacks ---

  defp add_modal_events(igniter, live_module, assign_key, open_event, close_event) do
    event_code = modal_event_code(assign_key, open_event, close_event)

    Igniter.Project.Module.find_and_update_module!(igniter, live_module, fn zipper ->
      {:ok, Igniter.Code.Common.add_code(zipper, event_code)}
    end)
  end

  defp modal_event_code(assign_key, open_event, close_event) do
    """
    # Modal: #{open_event}

    @impl true
    def handle_event("#{open_event}", _params, socket) do
      {:noreply, assign(socket, #{assign_key}: true)}
    end

    @impl true
    def handle_event("#{close_event}", _params, socket) do
      {:noreply, assign(socket, #{assign_key}: false)}
    end
    """
  end

  # --- LiveView Context: Add modal state to page_data ---

  defp add_modal_state(igniter, context_module, assign_key) do
    {module_exists, igniter} = Igniter.Project.Module.module_exists(igniter, context_module)

    if module_exists do
      Igniter.Project.Module.find_and_update_module!(igniter, context_module, fn zipper ->
        case Igniter.Code.Function.move_to_def(zipper, :page_data, 2) do
          {:ok, _zipper} ->
            # page_data exists; add a helper function for default modal assigns
            # and add a notice for the user to merge it
            {:ok, Igniter.Code.Common.add_code(zipper, modal_defaults_code(assign_key))}

          :error ->
            # No page_data function; add the defaults helper anyway
            {:ok, Igniter.Code.Common.add_code(zipper, modal_defaults_code(assign_key))}
        end
      end)
      |> Igniter.add_notice("""
      Remember to merge modal defaults into your page_data return value:

          def page_data(params, socket) do
            # ... existing code ...
            {:ok, Map.merge(page_data, modal_defaults())}
          end
      """)
    else
      Igniter.add_warning(igniter, "Could not find context module #{inspect(context_module)}")
    end
  end

  defp modal_defaults_code(assign_key) do
    """
    def modal_defaults do
      %{#{assign_key}: false}
    end
    """
  end

  # --- HEEx Template: Append modal markup ---

  defp add_modal_template(igniter, live_module, modal_name, modal_title, assign_key, close_event) do
    heex_path =
      igniter
      |> Igniter.Project.Module.proper_location(live_module)
      |> String.replace(~r/\.ex$/, ".html.heex")

    modal_markup = modal_template_code(modal_name, modal_title, assign_key, close_event)

    if Igniter.exists?(igniter, heex_path) do
      Igniter.update_file(igniter, heex_path, fn source ->
        current_content = Rewrite.Source.get(source, :content)
        Rewrite.Source.update(source, :content, current_content <> "\n" <> modal_markup)
      end)
    else
      Igniter.add_notice(igniter, """
      Could not find HEEx template at #{heex_path}.
      Add this modal markup to your template:

      #{modal_markup}
      """)
    end
  end

  defp modal_template_code(modal_name, modal_title, assign_key, close_event) do
    modal_id = String.replace(to_string(modal_name), "_", "-") <> "-modal"

    """
    <.modal :if={@#{assign_key}} id="#{modal_id}" show on_cancel={JS.push("#{close_event}")}>
      <:title>#{modal_title}</:title>
      <p>Modal content goes here.</p>
      <:actions>
        <.button phx-click="#{close_event}">Cancel</.button>
      </:actions>
    </.modal>
    """
  end
end
