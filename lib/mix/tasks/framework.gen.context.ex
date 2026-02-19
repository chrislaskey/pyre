defmodule Mix.Tasks.Framework.Gen.Context do
  @moduledoc """
  Generates a context module and schema from templates.

  Usage:
      mix framework.gen.context AppName.Contexts.Schema

  Example:
      mix framework.gen.context Accounts.Examples.Example

  This will create:
    - lib/accounts/contexts/examples/examples.ex (context module)
    - lib/accounts/contexts/examples/example.ex (schema module)
  """
  use Mix.Task

  @shortdoc "Generates a context and schema from templates"

  @impl Mix.Task
  def run([full_module_name]) do
    {app_name, context_name, schema_name} = parse_module_name(full_module_name)

    context_content = generate_context(app_name, context_name, schema_name)
    schema_content = generate_schema(app_name, context_name, schema_name)

    context_path = output_path(app_name, context_name, context_name)
    schema_path = output_path(app_name, context_name, schema_name)

    File.mkdir_p!(Path.dirname(context_path))

    File.write!(context_path, context_content)
    Mix.shell().info("Created #{context_path}")

    File.write!(schema_path, schema_content)
    Mix.shell().info("Created #{schema_path}")
  end

  def run(_) do
    Mix.shell().error("Usage: mix framework.gen.context AppName.Contexts.Schema")
  end

  defp parse_module_name(full_module_name) do
    parts = String.split(full_module_name, ".")

    app_name = List.first(parts)
    schema_name = List.last(parts)
    context_name = parts |> Enum.slice(1..-2//1) |> Enum.join(".")

    {app_name, context_name, schema_name}
  end

  defp generate_context(app_name, context_name, schema_name) do
    template_path()
    |> Path.join("context.ex.example")
    |> File.read!()
    |> String.replace("Framework", app_name)
    |> String.replace("Context", context_name)
    |> String.replace("Schema", schema_name)
    |> restore_reserved(app_name, schema_name)
  end

  defp generate_schema(app_name, context_name, schema_name) do
    template_path()
    |> Path.join("schema.ex.example")
    |> File.read!()
    |> String.replace("Framework", app_name)
    |> String.replace("Context", context_name)
    |> String.replace("Schema", schema_name)
    |> restore_reserved(app_name, schema_name)
  end

  defp restore_reserved(content, app_name, schema_name) do
    content
    |> String.replace("#{app_name}.Repo", "Framework.Repo")
    |> String.replace("#{app_name}.PubSub", "Framework.PubSub")
    |> String.replace("use Ecto.#{schema_name}", "use Ecto.Schema")
  end

  defp output_path(app_name, context_name, module_name) do
    app_dir = Macro.underscore(app_name)
    context_dir = Macro.underscore(context_name)
    filename = Macro.underscore(module_name) <> ".ex"

    Path.join(["lib", app_dir, "contexts", context_dir, filename])
  end

  defp template_path do
    Path.join([__DIR__, "templates"])
  end
end
