defmodule Mix.Tasks.Pyre.Gen.Filter do
  @moduledoc """
  Adds a filter function to an existing context module using Igniter.

  This task demonstrates Igniter's power for modifying existing code. It finds
  the specified context module by its AST definition (regardless of file location)
  and adds a `list_by_<field>` function that filters records by the given field.

  ## Usage

      mix pyre.gen.filter ContextModule field_name

  ## Examples

      mix pyre.gen.filter Accounts.Products status
      # => Adds `list_by_status/2` to the Accounts.Products context

      mix pyre.gen.filter Accounts.Products category --repo Example.Repo
      # => Adds `list_by_category/2` using a custom repo

  ## Options

    * `--repo` - Repo module name (default: `Framework.Repo`)

  The generated function follows the same pattern as existing context functions,
  using `@default_preloads` and the configured Repo module.

  """
  @shortdoc "Adds a filter function to an existing context"

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      positional: [:context_module, :field_name],
      schema: [repo: :string],
      defaults: [repo: "Framework.Repo"],
      example: "mix pyre.gen.filter Accounts.Products status"
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    context_input = igniter.args.positional.context_module
    field_name = igniter.args.positional.field_name
    repo = igniter.args.options[:repo]

    context_module = Module.concat(String.split(context_input, "."))
    field_atom = String.to_atom(field_name)
    function_name = :"list_by_#{field_name}"

    filter_code = filter_function_code(function_name, field_atom, repo)

    Igniter.Project.Module.find_and_update_module!(igniter, context_module, fn zipper ->
      {:ok, Igniter.Code.Common.add_code(zipper, filter_code)}
    end)
  end

  defp filter_function_code(function_name, field_atom, repo) do
    """
    @spec #{function_name}(any(), list()) :: list()
    def #{function_name}(value, options \\\\ []) do
      Schema
      |> where([record], record.#{field_atom} == ^value)
      |> preload(^Keyword.get(options, :preload, @default_preloads))
      |> #{repo}.all()
    end
    """
  end
end
