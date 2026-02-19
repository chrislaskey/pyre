defmodule Mix.Tasks.Pyre.Run do
  @moduledoc """
  Runs the multi-agent pipeline to build a Phoenix feature.

  Five specialized LLM agents (Product Manager, Designer, Programmer,
  Test Writer, Code Reviewer) collaborate serially to implement the feature.

  ## Usage

      mix pyre.run "Build a products listing page"

  ## Options

    * `--fast` — Use the fastest (haiku) model for all agents
    * `--dry-run` — Print commands without executing them
    * `--project-dir` — Working directory for the agents (default: `.`)

  ## Output

  Artifacts are written to `priv/pyre/runs/<timestamp>/`:
    - `00_feature.md` — Original feature request
    - `01_requirements.md` — Product Manager output
    - `02_design_spec.md` — Designer output
    - `03_implementation_summary.md` — Programmer output
    - `04_test_summary.md` — Test Writer output
    - `05_review_verdict.md` — Code Reviewer verdict (APPROVE/REJECT)
  """
  @shortdoc "Runs multi-agent pipeline to build a Phoenix feature"

  use Mix.Task

  @switches [fast: :boolean, dry_run: :boolean, project_dir: :string]
  @aliases [f: :fast, d: :dry_run, p: :project_dir]

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, switches: @switches, aliases: @aliases)

    feature_description =
      case args do
        [desc | _] ->
          desc

        [] ->
          Mix.raise("""
          Usage: mix pyre.run "feature description"

          Example: mix pyre.run "Build a products listing page"
          """)
      end

    orchestrator_opts = [
      fast: Keyword.get(opts, :fast, false),
      dry_run: Keyword.get(opts, :dry_run, false),
      project_dir: Keyword.get(opts, :project_dir, ".")
    ]

    case Pyre.Agents.Orchestrator.run(feature_description, orchestrator_opts) do
      :ok ->
        Mix.shell().info("\nPipeline completed successfully.")

      {:error, reason} ->
        Mix.raise("Pipeline failed: #{inspect(reason)}")
    end
  end
end
