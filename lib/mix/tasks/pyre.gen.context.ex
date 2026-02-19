defmodule Mix.Tasks.Pyre.Gen.Context do
  @moduledoc """
  Generates a context module and schema using Igniter.

  Unlike `framework.gen.context`, this task uses Igniter's AST-based code
  generation instead of string replacement templates. This produces properly
  formatted code, supports dry-run previews, and enables composability with
  other Igniter tasks.

  ## Usage

      mix pyre.gen.context App.Contexts.Schema

  ## Examples

      mix pyre.gen.context Accounts.Products.Product

  This will create:
    - `Accounts.Products` context module with CRUD operations
    - `Accounts.Products.Product` schema module with changeset

  ## Options

    * `--repo` - Repo module name (default: `Framework.Repo`)

  """
  @shortdoc "Generates a context and schema using Igniter"

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      positional: [:module_name],
      schema: [repo: :string],
      defaults: [repo: "Framework.Repo"],
      example: "mix pyre.gen.context Accounts.Products.Product"
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    module_input = igniter.args.positional.module_name
    parts = String.split(module_input, ".")

    if length(parts) < 3 do
      Igniter.add_issue(igniter, """
      Expected at least 3 parts in module name (e.g., App.Context.Schema).
      Got: #{module_input}
      """)
    else
      schema_name = List.last(parts)
      schema_module = Module.concat(parts)
      context_module = Module.concat(Enum.drop(parts, -1))
      table_name = schema_name |> Macro.underscore() |> Inflex.pluralize()
      repo = igniter.args.options[:repo]

      igniter
      |> create_context(context_module, schema_name, repo)
      |> create_schema(schema_module, schema_name, table_name)
    end
  end

  defp create_context(igniter, context_module, schema_name, repo) do
    context_code = context_module_code(context_module, schema_name, repo)
    Igniter.Project.Module.create_module(igniter, context_module, context_code)
  end

  defp create_schema(igniter, schema_module, schema_name, table_name) do
    schema_code = schema_module_code(schema_module, schema_name, table_name)
    Igniter.Project.Module.create_module(igniter, schema_module, schema_code)
  end

  defp context_module_code(context_module, schema_name, repo) do
    """
    @moduledoc \"\"\"
    Context for #{schema_name} records.

    Do NOT add any use-case specific functions to this file. It is generic on
    purpose. It is the responsibility of the callers to pass the correct `params`
    into the functions. Create use-case specific functions or context modules closer
    to the business logic.
    \"\"\"

    import Ecto.Query, except: [update: 2]

    alias #{inspect(context_module)}.#{schema_name}, as: Schema

    @default_preloads []
    @default_upsert_get_by_keys [:name]

    @spec list(list()) :: list()
    def list(options \\\\ []) do
      Schema
      |> preload(^Keyword.get(options, :preload, @default_preloads))
      |> #{repo}.all()
    end

    @spec get(binary() | integer(), list()) :: Schema.t() | nil
    def get(id, options \\\\ []) do
      Schema
      |> preload(^Keyword.get(options, :preload, @default_preloads))
      |> #{repo}.get(id)
    end

    @spec get_by(list(), list()) :: Schema.t() | nil
    def get_by(values, options \\\\ []) do
      Schema
      |> preload(^Keyword.get(options, :preload, @default_preloads))
      |> #{repo}.get_by(values)
    end

    @spec fetch(binary() | integer(), list()) :: {:ok, Schema.t()} | {:error, atom()}
    def fetch(id, options \\\\ []) do
      case get(id, options) do
        nil -> {:error, :not_found}
        record -> {:ok, record}
      end
    end

    @spec create(map()) :: {:ok, Schema.t()} | {:error, Ecto.Changeset.t()}
    def create(params) do
      %Schema{}
      |> Schema.changeset(params)
      |> #{repo}.insert()
    end

    @spec update(Schema.t(), map()) :: {:ok, Schema.t()} | {:error, Ecto.Changeset.t()}
    def update(record, params) do
      record
      |> Schema.changeset(params)
      |> #{repo}.update()
    end

    @spec upsert(map(), list()) :: {:ok, Schema.t()} | {:error, Ecto.Changeset.t()}
    def upsert(params, options \\\\ []) do
      get_by_keys =
        options
        |> Keyword.get(:keys, @default_upsert_get_by_keys)
        |> Enum.map(fn key ->
          {key, Map.get(params, key) || Map.get(params, to_string(key))}
        end)

      case get_by(get_by_keys) do
        nil -> create(params)
        record -> update(record, params)
      end
    end

    @spec delete(Schema.t()) :: {:ok, Schema.t()} | {:error, Ecto.Changeset.t()}
    def delete(record) do
      #{repo}.delete(record)
    end
    """
  end

  defp schema_module_code(_schema_module, schema_name, table_name) do
    """
    @moduledoc \"\"\"
    Ecto schema and changesets for #{schema_name}.
    \"\"\"

    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "#{table_name}" do
      # Replace with fields
    end

    @required []
    @castable @required ++ []

    def changeset(record, attrs) do
      record
      |> cast(attrs, @castable)
      |> validate_required(@required)
    end
    """
  end
end
