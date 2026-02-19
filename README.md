## Pyre

Multi-agent LLM framework for rapid Phoenix development.

Pyre orchestrates five specialized LLM agents — Product Manager, Designer,
Programmer, Test Writer, and Code Reviewer — to implement features in your
Phoenix application. Each agent has a persona that guides its output, and
the pipeline includes a review loop that iterates until the code reviewer
approves.

### Installation

Add `pyre` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pyre, git: "https://github.com/chrislaskey/pyre", branch: "main"}
  ]
end
```

Then run the installer to copy persona files and set up the runs directory:

```bash
mix deps.get
mix pyre.install
```

This creates:

- `priv/pyre/personas/` — Editable persona files for each agent
- `priv/pyre/runs/.gitkeep` — Directory where pipeline artifacts are stored
- `.gitignore` entries to exclude run output from version control

### Usage

Run the pipeline with a feature description:

```bash
mix pyre.run "Build a products listing page with sorting and filtering"
```

#### Options

| Flag | Short | Description |
|------|-------|-------------|
| `--fast` | `-f` | Use the fastest (haiku) model for all agents |
| `--dry-run` | `-d` | Print commands without executing them |
| `--project-dir` | `-p` | Working directory for agents (default: `.`) |

#### Output

Each run creates a timestamped directory in `priv/pyre/runs/` containing:

| File | Agent | Content |
|------|-------|---------|
| `00_feature.md` | — | Original feature request |
| `01_requirements.md` | Product Manager | User stories and acceptance criteria |
| `02_design_spec.md` | Designer | UI/UX specifications |
| `03_implementation_summary.md` | Programmer | Code changes made |
| `04_test_summary.md` | Test Writer | Tests written |
| `05_review_verdict.md` | Code Reviewer | APPROVE or REJECT with feedback |

### Customization

After installation, edit the persona files in `priv/pyre/personas/` to
customize agent behavior for your project. The installer will not overwrite
files that already exist, so your changes are preserved across updates.

### Generators

Pyre includes Igniter-based generators that agents use during the pipeline:

- `mix pyre.gen.context` — Generates a context module with CRUD functions
- `mix pyre.gen.live` — Generates LiveView pages with index/show views
- `mix pyre.gen.modal` — Adds a modal component to a LiveView
- `mix pyre.gen.filter` — Adds a filter function to an existing context
