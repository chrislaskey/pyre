# Igniter for Phoenix: A Practical Guide

Igniter is a code generation and project patching framework for Elixir. Unlike traditional generators that dump template files and hope for the best, Igniter works with your project's AST (Abstract Syntax Tree) to create, modify, and compose code changes safely.

This guide teaches Igniter through practical Phoenix LiveView examples. Each section builds on the last, moving from "create a file" to "find an existing module and surgically add code to it."

## Table of Contents

- [How Igniter Works](#how-igniter-works)
- [Part 1: Your First Igniter Task](#part-1-your-first-igniter-task)
- [Part 2: Creating Modules](#part-2-creating-modules)
- [Part 3: Creating Non-Elixir Files](#part-3-creating-non-elixir-files)
- [Part 4: Modifying Existing Modules](#part-4-modifying-existing-modules)
- [Part 5: Working with Multiple Files](#part-5-working-with-multiple-files)
- [Part 6: Phoenix-Specific Helpers](#part-6-phoenix-specific-helpers)
- [Part 7: Composing Tasks](#part-7-composing-tasks)
- [Part 8: String Escaping in Code Templates](#part-8-string-escaping-in-code-templates)
- [API Quick Reference](#api-quick-reference)

---

## How Igniter Works

### The Core Idea

Every Igniter task follows the same pattern:

1. You receive an `Igniter.t()` struct (a builder that accumulates changes)
2. You call functions that describe what to create or modify
3. Igniter applies all changes at the end (or shows a dry-run preview)

```
igniter          # Start with the igniter struct
|> create_x()   # Describe changes (nothing written yet)
|> modify_y()   # More changes (still nothing written)
|> add_z()      # Even more changes
                 # Igniter applies everything at the end
```

No files are written until the very end. This means you can preview changes with `--dry-run`, and if anything goes wrong, nothing is half-written.

### Key Concepts

**The Igniter struct** is threaded through every operation. Always use the return value:

```elixir
# CORRECT - thread the igniter through
igniter
|> step_one()
|> step_two()

# WRONG - discards changes from step_one
step_one(igniter)
step_two(igniter)
```

**Zippers** are how Igniter navigates code. Think of a zipper as a cursor in a text editor, but for AST nodes instead of characters. You can move the cursor to a specific function, module attribute, or expression, then insert or replace code at that position.

```elixir
# A zipper updater function: receives a zipper, returns {:ok, zipper} or :error
fn zipper ->
  {:ok, Igniter.Code.Common.add_code(zipper, "def hello, do: :world")}
end
```

**`create_module` vs `find_and_update_module!`** is the fundamental choice:
- Use `create_module` when the module doesn't exist yet
- Use `find_and_update_module!` when you need to modify an existing module
- Use `find_and_update_or_create_module` when it might or might not exist

---

## Part 1: Your First Igniter Task

### The Skeleton

Every Igniter mix task implements two callbacks: `info/2` and `igniter/1`.

```elixir
defmodule Mix.Tasks.MyApp.Gen.Thing do
  @shortdoc "Generates a thing"
  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      positional: [:name],
      schema: [verbose: :boolean],
      defaults: [verbose: false],
      example: "mix my_app.gen.thing MyModule"
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    name = igniter.args.positional.name
    verbose? = igniter.args.options[:verbose]

    # ... do work with the igniter ...
    igniter
  end
end
```

### The `info/2` Callback

This tells Igniter how to parse CLI arguments. The struct fields you'll use most:

| Field | Purpose | Example |
|---|---|---|
| `positional` | Named positional args (order matters) | `[:module_name, :field]` |
| `schema` | Named flags (OptionParser style) | `[repo: :string, exact: :boolean]` |
| `defaults` | Default values for flags | `[repo: "MyApp.Repo"]` |
| `example` | Shown in `mix help` | `"mix my_app.gen.thing Foo"` |
| `composes` | Other tasks this one calls | `["my_app.gen.schema"]` |

### The `igniter/1` Callback

This is where all the work happens. You receive the igniter with parsed args and return it after describing your changes.

Access parsed arguments:

```elixir
def igniter(igniter) do
  # Positional args (declared in info)
  module_name = igniter.args.positional.module_name

  # Named options (from schema)
  repo = igniter.args.options[:repo]

  igniter
end
```

### Running Your Task

```bash
# Normal run - applies changes
mix my_app.gen.thing MyModule

# Dry run - shows what would change without writing anything
mix my_app.gen.thing MyModule --dry-run

# With flags
mix my_app.gen.thing MyModule --repo MyApp.Repo --verbose
```

The `--dry-run` flag is built in to every Igniter task for free. This is one of the biggest advantages over hand-rolled generators.

---

## Part 2: Creating Modules

### `create_module` - The Workhorse

This is the function you'll use most. It creates an Elixir module at the correct file path based on the module name.

```elixir
Igniter.Project.Module.create_module(igniter, MyApp.Accounts.User, """
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email])
    |> validate_required([:name, :email])
  end
""")
```

**Key detail:** You provide the module _body_, not the full `defmodule` wrapper. Igniter adds the `defmodule MyApp.Accounts.User do ... end` automatically and places the file at `lib/my_app/accounts/user.ex`.

### How File Paths Work

Igniter uses `proper_location/2` to determine where a module should live:

| Module Name | File Path |
|---|---|
| `MyApp.Accounts` | `lib/my_app/accounts.ex` |
| `MyApp.Accounts.User` | `lib/my_app/accounts/user.ex` |
| `MyAppWeb.UserLive.Index` | `lib/my_app_web/user_live/index.ex` |

You can also query this directly:

```elixir
path = Igniter.Project.Module.proper_location(igniter, MyApp.Accounts.User)
# => "lib/my_app/accounts/user.ex"
```

### Using Interpolation for Dynamic Modules

Since module contents are just strings, use standard Elixir interpolation:

```elixir
def igniter(igniter) do
  module_name = Module.concat(["MyApp", "Accounts", "User"])
  repo = "MyApp.Repo"

  Igniter.Project.Module.create_module(igniter, module_name, """
    alias #{inspect(module_name)}, as: Schema

    def list do
      #{repo}.all(Schema)
    end
  """)
end
```

Use `inspect(module)` to turn a module atom into its string representation (e.g., `MyApp.Accounts.User`).

### Checking If a Module Exists

```elixir
{exists?, igniter} = Igniter.Project.Module.module_exists(igniter, MyApp.Accounts.User)
```

**Important:** Always use the returned `igniter`, not the original. `module_exists` may update the igniter's internal file index.

---

## Part 3: Creating Non-Elixir Files

For HEEx templates, JavaScript, CSS, or any other file type, use `create_new_file`:

```elixir
Igniter.create_new_file(igniter, "lib/my_app_web/live/user_live/index.html.heex", """
<div>
  <h1>Users</h1>
  <div :for={user <- @users}>
    {user.name}
  </div>
</div>
""")
```

A useful pattern is to derive the template path from the LiveView module path:

```elixir
defp heex_path_for_module(igniter, module) do
  igniter
  |> Igniter.Project.Module.proper_location(module)
  |> String.replace(~r/\.ex$/, ".html.heex")
end
```

### Checking If a File Exists

```elixir
if Igniter.exists?(igniter, path) do
  # update it
else
  # create it or warn
end
```

---

## Part 4: Modifying Existing Modules

This is where Igniter shines compared to template-based generators. You can find a module anywhere in the project and surgically add code to it.

### Adding a Function to an Existing Module

```elixir
Igniter.Project.Module.find_and_update_module!(igniter, MyApp.Accounts, fn zipper ->
  {:ok, Igniter.Code.Common.add_code(zipper, """
    def list_active_users do
      User
      |> where([u], u.active == true)
      |> Repo.all()
    end
  """)}
end)
```

The zipper starts positioned at the module body. `add_code` inserts after the last existing expression by default. The result is the function appended at the bottom of the module, just before the closing `end`.

### Controlling Placement

```elixir
# Add BEFORE the current position (e.g., at the top of the module body)
Igniter.Code.Common.add_code(zipper, code, placement: :before)

# Add AFTER the current position (default)
Igniter.Code.Common.add_code(zipper, code, placement: :after)
```

### Navigating to a Specific Function

You can move the zipper to a specific function definition before inserting:

```elixir
Igniter.Project.Module.find_and_update_module!(igniter, MyApp.Accounts, fn zipper ->
  case Igniter.Code.Function.move_to_def(zipper, :list, 1) do
    {:ok, _zipper} ->
      # Found `def list/1` - add our code after it at module level
      {:ok, Igniter.Code.Common.add_code(zipper, new_function_code)}

    :error ->
      # Function doesn't exist - still add at the end
      {:ok, Igniter.Code.Common.add_code(zipper, new_function_code)}
  end
end)
```

### Create If Missing, Update If Present

For idempotent generators that work whether or not the module already exists:

```elixir
Igniter.Project.Module.find_and_update_or_create_module(
  igniter,
  MyApp.Accounts,
  # Default content if creating from scratch:
  """
    @moduledoc "Accounts context."
    import Ecto.Query
  """,
  # Updater if the module already exists:
  fn zipper ->
    {:ok, Igniter.Code.Common.add_code(zipper, new_function)}
  end
)
```

### Real Example: Adding a Filter Function

Here is the core of `pyre.gen.filter`. Given a context module and field name, it adds a filter function:

```elixir
def igniter(igniter) do
  context_module = Module.concat(String.split(context_input, "."))
  field_atom = String.to_atom(field_name)
  function_name = :"list_by_#{field_name}"

  filter_code = """
    def #{function_name}(value, options \\\\ []) do
      Schema
      |> where([record], record.#{field_atom} == ^value)
      |> preload(^Keyword.get(options, :preload, @default_preloads))
      |> Repo.all()
    end
  """

  Igniter.Project.Module.find_and_update_module!(igniter, context_module, fn zipper ->
    {:ok, Igniter.Code.Common.add_code(zipper, filter_code)}
  end)
end
```

Running `mix pyre.gen.filter Accounts.Products status` finds `Accounts.Products` wherever it lives and appends `list_by_status/2`.

---

## Part 5: Working with Multiple Files

A single Igniter task can create and modify multiple files in one atomic operation. Thread the igniter through each step:

```elixir
def igniter(igniter) do
  igniter
  |> create_live_view_module(live_module, web_module, context_module)
  |> create_context_module(context_module, pubsub, topic)
  |> create_heex_template(live_module, web_module)
end
```

### Real Example: Adding a Modal (3 files at once)

The `pyre.gen.modal` task modifies three files in a single run:

```elixir
def igniter(igniter) do
  igniter
  |> add_event_handlers_to_live_view(live_module, ...)
  |> add_defaults_to_context(context_module, ...)
  |> append_markup_to_template(live_module, ...)
end
```

**1. Modify the LiveView module** (add handle_event callbacks):

```elixir
defp add_event_handlers(igniter, live_module, open_event, close_event, assign_key) do
  Igniter.Project.Module.find_and_update_module!(igniter, live_module, fn zipper ->
    {:ok, Igniter.Code.Common.add_code(zipper, """
      def handle_event("#{open_event}", _params, socket) do
        {:noreply, assign(socket, #{assign_key}: true)}
      end

      def handle_event("#{close_event}", _params, socket) do
        {:noreply, assign(socket, #{assign_key}: false)}
      end
    """)}
  end)
end
```

**2. Modify the Context module** (add modal_defaults function):

```elixir
defp add_modal_defaults(igniter, context_module, assign_key) do
  Igniter.Project.Module.find_and_update_module!(igniter, context_module, fn zipper ->
    {:ok, Igniter.Code.Common.add_code(zipper, """
      def modal_defaults do
        %{#{assign_key}: false}
      end
    """)}
  end)
end
```

**3. Modify the HEEx template** (append modal markup):

```elixir
defp append_modal_markup(igniter, heex_path, modal_markup) do
  Igniter.update_file(igniter, heex_path, fn source ->
    current = Rewrite.Source.get(source, :content)
    Rewrite.Source.update(source, :content, current <> "\n" <> modal_markup)
  end)
end
```

All three changes show up together in `--dry-run` output, and all three are applied (or none) as a unit.

### Conditional Modifications

Check if a module exists before trying to modify it:

```elixir
{exists?, igniter} = Igniter.Project.Module.module_exists(igniter, context_module)

if exists? do
  Igniter.Project.Module.find_and_update_module!(igniter, context_module, fn zipper ->
    {:ok, Igniter.Code.Common.add_code(zipper, new_code)}
  end)
else
  Igniter.add_warning(igniter, "Module #{inspect(context_module)} not found, skipping.")
end
```

### Communicating with the User

Igniter has three levels of messaging:

```elixir
# Informational - shown after success
Igniter.add_notice(igniter, "Remember to add the route to your router.")

# Warning - shown but doesn't prevent file writes
Igniter.add_warning(igniter, "Module not found, some changes were skipped.")

# Issue - prevents ALL file writes
Igniter.add_issue(igniter, "Invalid module name: #{name}")
```

---

## Part 6: Phoenix-Specific Helpers

Igniter includes helpers for common Phoenix operations in `Igniter.Libs.Phoenix`.

### Router Modification

```elixir
# Add a new scope with routes
igniter
|> Igniter.Libs.Phoenix.add_scope("/admin", """
  pipe_through [:browser, :require_admin]
  live "/dashboard", DashboardLive.Index
""")

# Add routes to an existing scope
igniter
|> Igniter.Libs.Phoenix.append_to_scope("/", """
  live "/products", ProductsLive.Index
""")

# Add a new pipeline
igniter
|> Igniter.Libs.Phoenix.add_pipeline(:api_v2, """
  plug :accepts, ["json"]
  plug :fetch_api_token
""")
```

### Discovering Project Structure

```elixir
# Get the web module name (e.g., MyAppWeb)
web_module = Igniter.Libs.Phoenix.web_module(igniter)

# Build a module name under the web namespace
module = Igniter.Libs.Phoenix.web_module_name(igniter, "ProductsLive.Index")
# => MyAppWeb.ProductsLive.Index

# Find all routers in the project
{igniter, routers} = Igniter.Libs.Phoenix.list_routers(igniter)

# Select a router (auto-selects if only one, prompts if multiple)
{igniter, router} = Igniter.Libs.Phoenix.select_router(igniter)
```

---

## Part 7: Composing Tasks

Tasks can call other tasks. This lets you build complex generators from simpler building blocks.

### Calling Another Task

```elixir
def igniter(igniter) do
  igniter
  |> do_my_work()
  |> Igniter.compose_task("pyre.gen.context", ["Accounts.Products.Product"])
end
```

**Important:** Declare composed tasks in your `info/2` callback so Igniter can merge their flag definitions:

```elixir
def info(_argv, _composing_task) do
  %Igniter.Mix.Task.Info{
    positional: [:name],
    composes: ["pyre.gen.context"]  # <-- declare it here
  }
end
```

### Passing State Between Tasks

Use `igniter.assigns` to share data:

```elixir
# In task A
igniter = Igniter.assign(igniter, :schema_module, MyApp.User)

# In task B (composed from A)
schema_module = igniter.assigns[:schema_module]
```

---

## Part 8: String Escaping in Code Templates

When writing Igniter tasks, your Elixir source file contains strings that represent generated Elixir code. This creates escaping challenges.

### Default Arguments (`\\`)

The `\\` default argument operator needs to survive two levels of parsing: your source file and the generated file.

```elixir
# In your mix task source code:
"""
def list(options \\\\ []) do
  # ...
end
"""

# At runtime, the string value is:
# def list(options \\ []) do

# Written to the generated .ex file as:
# def list(options \\ []) do   ← valid Elixir default argument
```

Rule: **`\\\\` in your source** becomes `\\` in the generated file.

### Heredoc Strings (`"""`)

To include `"""` inside your heredoc (e.g., for `@moduledoc`), escape the quotes:

```elixir
"""
@moduledoc \"\"\"
Documentation here.
\"\"\"

def hello, do: :world
"""
```

The `\"\"\"` does not match the heredoc terminator pattern because the `\` character prevents it. After escape processing, the output file gets proper `"""`.

### Elixir Interpolation in Generated Code

If the generated code needs `#{...}` interpolation (not your template interpolation), use `~S` sigils:

```elixir
defp my_template_code do
  log_line = ~S'Logger.error("[#{__MODULE__}] Error: #{inspect(error)}")'

  """
  def log_error(error) do
    #{log_line}
  end
  """
end
```

Here `~S` prevents interpolation when defining `log_line`. Then `#{log_line}` in the heredoc interpolates the _value_ (which contains literal `#{...}`) into the output.

### Quick Reference

| You want in the output | Write in your source |
|---|---|
| `\\` (default arg) | `\\\\` |
| `"""` (heredoc) | `\"\"\"` |
| `#{expr}` (literal, not interpolated) | Use `~S` sigil + interpolate the variable |
| `#{expr}` (interpolated at generation time) | `#{expr}` (normal interpolation) |

---

## API Quick Reference

### Core (`Igniter`)

| Function | What It Does |
|---|---|
| `create_new_file(ign, path, content)` | Create a file (error if exists) |
| `create_or_update_elixir_file(ign, path, content, updater)` | Create or update an .ex file |
| `update_elixir_file(ign, path, updater)` | Update an existing .ex file via zipper |
| `update_file(ign, path, updater)` | Update any file via Rewrite.Source |
| `exists?(ign, path)` | Check if a file exists |
| `add_notice(ign, msg)` | Show info after completion |
| `add_warning(ign, msg)` | Show warning (non-blocking) |
| `add_issue(ign, msg)` | Block all writes with an error |
| `compose_task(ign, task, argv)` | Run another Igniter task |
| `assign(ign, key, value)` | Store state for composed tasks |

### Modules (`Igniter.Project.Module`)

| Function | What It Does |
|---|---|
| `create_module(ign, module, body)` | Create a module at its proper path |
| `find_and_update_module!(ign, module, updater)` | Find and modify an existing module (raises if missing) |
| `find_and_update_or_create_module(ign, mod, body, updater)` | Update if exists, create if not |
| `module_exists(ign, module)` | Returns `{boolean, igniter}` |
| `proper_location(ign, module)` | Get the conventional file path for a module |

### Zipper Navigation (`Igniter.Code.Common`)

| Function | What It Does |
|---|---|
| `add_code(zipper, code, opts)` | Insert code (`:placement` => `:before` or `:after`) |
| `replace_code(zipper, code)` | Replace code at current position |
| `move_to_pattern(zipper, pattern)` | Move to a node matching an AST pattern |
| `move_to_cursor(zipper, pattern)` | Move to a `__cursor__()` marker in a pattern |

### Functions (`Igniter.Code.Function`)

| Function | What It Does |
|---|---|
| `move_to_def(zipper, name, arity)` | Navigate to a `def`/`defp` |
| `move_to_function_call(zipper, name, arity, pred)` | Navigate to a function call |
| `update_nth_argument(zipper, index, updater)` | Update the nth argument of a call |

### Phoenix (`Igniter.Libs.Phoenix`)

| Function | What It Does |
|---|---|
| `add_scope(ign, route, contents)` | Add a scope to the router |
| `append_to_scope(ign, route, contents)` | Add routes to an existing scope |
| `add_pipeline(ign, name, contents)` | Add a pipeline to the router |
| `append_to_pipeline(ign, name, contents)` | Add plugs to an existing pipeline |
| `web_module(ign)` | Get the web module (e.g., `MyAppWeb`) |
| `web_module_name(ign, suffix)` | Build a name under the web namespace |
| `select_router(ign)` | Select a router (auto or prompt) |

### Ecto (`Igniter.Libs.Ecto`)

| Function | What It Does |
|---|---|
| `gen_migration(ign, repo, name, opts)` | Generate a migration file |
| `list_repos(ign)` | List all Ecto repos |
| `select_repo(ign)` | Select a repo (auto or prompt) |

### Config (`Igniter.Project.Config`)

| Function | What It Does |
|---|---|
| `configure(ign, file, app, path, value, opts)` | Set a config value |
| `configure_new(ign, file, app, path, value)` | Set only if not already set |

### Application (`Igniter.Project.Application`)

| Function | What It Does |
|---|---|
| `add_new_child(ign, child, opts)` | Add a child to the supervision tree |
| `app_name(ign)` | Get the OTP application name |

---

## Pyre Task Examples

The tasks in `lib/mix/tasks/pyre.gen.*.ex` demonstrate each pattern:

| Task | Igniter Pattern | Phoenix Use Case |
|---|---|---|
| `pyre.gen.context` | `create_module` | Generate a context + schema from scratch |
| `pyre.gen.live` | `create_module` + `create_new_file` | Generate LiveView + Context + HEEx template |
| `pyre.gen.filter` | `find_and_update_module!` + `add_code` | Add a filter function to an existing context |
| `pyre.gen.modal` | `find_and_update_module!` + `update_file` | Add modal to an existing LiveView (3 files) |

### Typical Workflow

```bash
# 1. Generate context + schema
mix pyre.gen.context Accounts.Products.Product

# 2. Add a filter function to the context
mix pyre.gen.filter Accounts.Products status

# 3. Generate the LiveView page
mix pyre.gen.live ExampleWeb.ProductsLive

# 4. Add a confirmation modal to the LiveView
mix pyre.gen.modal ExampleWeb.ProductsLive confirm_delete

# Preview any step before applying:
mix pyre.gen.filter Accounts.Products category --dry-run
```

Each step is deterministic, composable, and produces consistent code regardless of who (or what) runs it.
