defmodule Mix.Tasks.Framework.Gen.Live do
  @moduledoc """
  Generates LiveView files from templates.

  Usage:
      mix framework.gen.live AppWeb.ProductsLive

  Examples:
      mix framework.gen.live AccountsWeb.Example
      # => AccountsWeb.ExamplesLive (auto-pluralized)

      mix framework.gen.live Accounts.Example
      # => AccountsWeb.ExamplesLive (auto-pluralized, auto-adds Web and Live)

      mix framework.gen.live Accounts.Examples.Example
      # => AccountsWeb.ExamplesLive (derives from schema name)

  Options:
      --exact    Use the exact name provided without pluralization

  Examples with options:
      mix framework.gen.live AccountsWeb.Example --exact
      # => AccountsWeb.ExampleLive (uses singular form)

      mix framework.gen.live AccountsWeb.Status --exact
      # => AccountsWeb.StatusLive (prevents "Statuses")

  This will create:
    - lib/accounts/web/live/examples/index.ex
    - lib/accounts/web/live/examples/index_context.ex
    - lib/accounts/web/live/examples/index.html.heex

  """
  use Mix.Task

  @shortdoc "Generates LiveView files from templates"

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [exact: :boolean]
      )

    case positional do
      [full_module_name] ->
        pluralize? = !opts[:exact]

        {app_web_name, page_name} = parse_module_name(full_module_name, pluralize?)

        Mix.shell().info("Generating #{app_web_name}.#{page_name}")

        generate_index(app_web_name, page_name)
        generate_index_context(app_web_name, page_name)
        generate_index_template(app_web_name, page_name)

      _ ->
        Mix.shell().error("""
        Usage: mix framework.gen.live AppWeb.ProductsLive [options]

        Options:
          --exact       Use exact name without pluralization
        """)
    end
  end

  defp parse_module_name(full_module_name, pluralize?) do
    parts = String.split(full_module_name, ".")

    case length(parts) do
      # "AccountsWeb.ExampleLive" -> ["AccountsWeb", "ExampleLive"]
      2 ->
        [app_part, page_part] = parts
        page_part = maybe_pluralize(page_part, pluralize?)

        {ensure_web_suffix(app_part), ensure_live_suffix(page_part)}

      # "Accounts.Examples.Example" -> derive AppWeb and SchemaLive
      n when n >= 3 ->
        app_name = List.first(parts)
        schema_name = List.last(parts)
        page_part = maybe_pluralize(schema_name, pluralize?)

        {ensure_web_suffix(app_name), ensure_live_suffix(page_part)}

      # Single part "Accounts" -> "AccountsWeb.AccountsLive"
      1 ->
        [app_part] = parts
        page_part = maybe_pluralize(app_part, pluralize?)

        {ensure_web_suffix(app_part), ensure_live_suffix(page_part)}
    end
  end

  defp maybe_pluralize(name, true), do: Inflex.pluralize(name)
  defp maybe_pluralize(name, false), do: name

  defp ensure_web_suffix(name) do
    if String.ends_with?(name, "Web") do
      name
    else
      name <> "Web"
    end
  end

  defp ensure_live_suffix(name) do
    if String.ends_with?(name, "Live") do
      name
    else
      name <> "Live"
    end
  end

  defp generate_index(app_web_name, page_name) do
    content =
      template_path()
      |> Path.join("live/index.ex.example")
      |> File.read!()
      |> replace_placeholders(app_web_name, page_name)
      |> restore_reserved(app_web_name, page_name)

    path = output_path(app_web_name, page_name, "index.ex.example")
    write_file(path, content)
  end

  defp generate_index_context(app_web_name, page_name) do
    content =
      template_path()
      |> Path.join("live/index_context.ex.example")
      |> File.read!()
      |> replace_placeholders(app_web_name, page_name)
      |> restore_reserved(app_web_name, page_name)

    path = output_path(app_web_name, page_name, "index_context.ex.example")
    write_file(path, content)
  end

  defp generate_index_template(app_web_name, page_name) do
    content =
      template_path()
      |> Path.join("live/index.html.heex")
      |> File.read!()
      |> replace_placeholders(app_web_name, page_name)
      |> restore_reserved(app_web_name, page_name)

    path = output_path(app_web_name, page_name, "index.html.heex")
    write_file(path, content)
  end

  defp replace_placeholders(content, app_web_name, page_name) do
    # Derive the pubsub topic from page name (e.g., "ExampleLive" -> "example")
    topic_name =
      page_name
      |> String.replace("Live", "")
      |> Macro.underscore()

    content
    |> String.replace("FrameworkWeb", app_web_name)
    |> String.replace("PageLive", page_name)
    |> String.replace(~s("page"), ~s("#{topic_name}"))
  end

  defp restore_reserved(content, app_web_name, _page_name) do
    content
    |> String.replace("#{app_web_name}.Repo", "Framework.Repo")
    |> String.replace("#{app_web_name}.PubSub", "Framework.PubSub")
  end

  defp output_path(app_web_name, page_name, filename) do
    # Convert "AccountsWeb" to "accounts/web"
    app_dir =
      app_web_name
      |> String.replace("Web", "/web")
      |> Macro.underscore()

    # Convert "ExampleLive" to "example"
    page_dir =
      page_name
      |> String.replace("Live", "")
      |> Macro.underscore()

    Path.join(["lib", app_dir, "live", page_dir, filename])
  end

  defp write_file(path, content) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    Mix.shell().info("Created #{path}")
  end

  defp template_path do
    Path.join([__DIR__, "templates"])
  end
end
