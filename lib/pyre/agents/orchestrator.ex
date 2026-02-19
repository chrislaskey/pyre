defmodule Pyre.Agents.Orchestrator.Stage do
  @moduledoc false
  defstruct [:name, :persona, :reads, :writes, :tools, :model, :permission_mode]

  @type t :: %__MODULE__{
          name: atom(),
          persona: atom(),
          reads: [String.t()],
          writes: String.t(),
          tools: [String.t()],
          model: String.t(),
          permission_mode: String.t()
        }
end

defmodule Pyre.Agents.Orchestrator do
  @moduledoc """
  Pipeline logic for multi-agent orchestration.

  Defines stages as data structs and executes them sequentially,
  with a review loop for the implementation/test/review cycle.
  """

  alias Pyre.Agents.{Artifact, Persona, Runner}
  alias Pyre.Agents.Orchestrator.Stage

  @max_review_cycles 3

  @stages [
    %Stage{
      name: :product_manager,
      persona: :product_manager,
      reads: [],
      writes: "01_requirements",
      tools: ~w(Read Glob Grep Write),
      model: "sonnet",
      permission_mode: "acceptEdits"
    },
    %Stage{
      name: :designer,
      persona: :designer,
      reads: ["01_requirements.md"],
      writes: "02_design_spec",
      tools: ~w(Read Glob Grep Write),
      model: "sonnet",
      permission_mode: "acceptEdits"
    },
    %Stage{
      name: :programmer,
      persona: :programmer,
      reads: ["01_requirements.md", "02_design_spec.md"],
      writes: "03_implementation_summary",
      tools: ~w(Read Glob Grep Write Edit Bash),
      model: "opus",
      permission_mode: "bypassPermissions"
    },
    %Stage{
      name: :test_writer,
      persona: :test_writer,
      reads: ["01_requirements.md", "02_design_spec.md", "03_implementation_summary.md"],
      writes: "04_test_summary",
      tools: ~w(Read Glob Grep Write Edit Bash),
      model: "sonnet",
      permission_mode: "bypassPermissions"
    },
    %Stage{
      name: :code_reviewer,
      persona: :code_reviewer,
      reads: [
        "01_requirements.md",
        "02_design_spec.md",
        "03_implementation_summary.md",
        "04_test_summary.md"
      ],
      writes: "05_review_verdict",
      tools: ~w(Read Glob Grep Write),
      model: "opus",
      permission_mode: "acceptEdits"
    }
  ]

  @doc """
  Returns the list of pipeline stages.
  """
  @spec stages() :: [Stage.t()]
  def stages, do: @stages

  @doc """
  Runs the full multi-agent pipeline for a feature description.

  ## Options

  - `:runner` — Function `(Runner.config() -> {:ok, integer()} | {:error, term()})`.
    Defaults to `&Runner.run/1`. Inject a mock for testing.
  - `:fast` — When `true`, overrides all models to `"haiku"`. Default `false`.
  - `:dry_run` — When `true`, prints commands without executing. Default `false`.
  - `:verbose` — When `true`, prints each command before running and reports exit codes. Default `false`.
  - `:project_dir` — Working directory for the claude CLI. Default `"."`.
  """
  @spec run(String.t(), keyword()) :: :ok | {:error, term()}
  def run(feature_description, opts \\ []) do
    runner = Keyword.get(opts, :runner, &Runner.run/1)
    fast? = Keyword.get(opts, :fast, false)
    dry_run? = Keyword.get(opts, :dry_run, false)
    verbose? = Keyword.get(opts, :verbose, false)
    project_dir = Keyword.get(opts, :project_dir, ".")
    working_dir = Path.expand(project_dir)

    runs_dir = Path.expand("priv/pyre/runs", File.cwd!())

    with {:ok, run_dir} <- Artifact.create_run_dir(runs_dir),
         :ok <- Artifact.write(run_dir, "00_feature", feature_description) do
      Mix.shell().info("Run directory: #{run_dir}")

      # Execute PM and Designer stages
      [pm_stage, designer_stage | _] = @stages

      with :ok <-
             execute_stage(
               pm_stage,
               feature_description,
               run_dir,
               working_dir,
               runner,
               fast?,
               dry_run?,
               verbose?
             ),
           :ok <-
             execute_stage(
               designer_stage,
               feature_description,
               run_dir,
               working_dir,
               runner,
               fast?,
               dry_run?,
               verbose?
             ) do
        # Enter review loop
        review_loop(feature_description, run_dir, working_dir, runner, fast?, dry_run?, verbose?, 1)
      end
    end
  end

  defp review_loop(_feature, _run_dir, _working_dir, _runner, _fast?, _dry_run?, _verbose?, cycle)
       when cycle > @max_review_cycles do
    Mix.shell().info("Max review cycles (#{@max_review_cycles}) reached. Stopping.")
    :ok
  end

  defp review_loop(feature_description, run_dir, working_dir, runner, fast?, dry_run?, verbose?, cycle) do
    [_, _, programmer_stage, test_writer_stage, reviewer_stage] = @stages

    # Build versioned stages for this cycle
    programmer = version_stage(programmer_stage, cycle)
    test_writer = version_stage(test_writer_stage, cycle)
    reviewer = version_stage(reviewer_stage, cycle)

    # On cycle 2+, add previous review verdict to programmer's and test_writer's reads
    programmer =
      if cycle > 1 do
        prev_verdict = Artifact.versioned_name("05_review_verdict", cycle - 1) <> ".md"
        %{programmer | reads: programmer.reads ++ [prev_verdict]}
      else
        programmer
      end

    test_writer =
      if cycle > 1 do
        prev_verdict = Artifact.versioned_name("05_review_verdict", cycle - 1) <> ".md"
        %{test_writer | reads: test_writer.reads ++ [prev_verdict]}
      else
        test_writer
      end

    # Update reviewer reads to point to this cycle's versioned artifacts
    reviewer = %{
      reviewer
      | reads: [
          "01_requirements.md",
          "02_design_spec.md",
          Artifact.versioned_name("03_implementation_summary", cycle) <> ".md",
          Artifact.versioned_name("04_test_summary", cycle) <> ".md"
        ]
    }

    with :ok <-
           execute_stage(
             programmer,
             feature_description,
             run_dir,
             working_dir,
             runner,
             fast?,
             dry_run?,
             verbose?
           ),
         :ok <-
           execute_stage(
             test_writer,
             feature_description,
             run_dir,
             working_dir,
             runner,
             fast?,
             dry_run?,
             verbose?
           ),
         :ok <-
           execute_stage(
             reviewer,
             feature_description,
             run_dir,
             working_dir,
             runner,
             fast?,
             dry_run?,
             verbose?
           ) do
      # Check verdict
      verdict_file = Artifact.versioned_name("05_review_verdict", cycle)

      case parse_verdict(run_dir, verdict_file) do
        :approve ->
          Mix.shell().info("Review: APPROVED (cycle #{cycle})")
          :ok

        :reject ->
          Mix.shell().info("Review: REJECTED (cycle #{cycle}), starting rework...")

          review_loop(
            feature_description,
            run_dir,
            working_dir,
            runner,
            fast?,
            dry_run?,
            verbose?,
            cycle + 1
          )
      end
    end
  end

  defp version_stage(stage, cycle) do
    %{stage | writes: Artifact.versioned_name(stage.writes, cycle)}
  end

  defp execute_stage(stage, feature_description, run_dir, working_dir, runner, fast?, dry_run?, verbose?) do
    Mix.shell().info("\n--- Stage: #{stage.name} ---")

    model = if fast?, do: "haiku", else: stage.model
    artifact_filename = stage.writes <> ".md"

    {:ok, system_prompt} = Persona.build_system_prompt(stage.persona)

    artifacts_content =
      case stage.reads do
        [] ->
          ""

        reads ->
          {:ok, content} = Artifact.assemble(run_dir, reads)
          content
      end

    prompt =
      Persona.build_prompt(feature_description, artifacts_content, run_dir, artifact_filename)

    config = %{
      prompt: prompt,
      system_prompt: system_prompt,
      allowed_tools: stage.tools,
      model: model,
      working_dir: working_dir,
      run_dir: run_dir,
      permission_mode: stage.permission_mode
    }

    if dry_run? do
      {cmd, args} = Runner.build_command(config)
      Mix.shell().info("[dry-run] #{cmd} #{Enum.join(args, " ")}")
      :ok
    else
      if verbose? do
        {cmd, args} = Runner.build_command(config)
        Mix.shell().info("[verbose] working_dir: #{working_dir}")
        Mix.shell().info("[verbose] run_dir:     #{run_dir}")
        Mix.shell().info("[verbose] model:       #{model}")
        Mix.shell().info("[verbose] permission:  #{stage.permission_mode}")
        Mix.shell().info("[verbose] cmd: #{cmd} #{Enum.join(args, " ")}")
      end

      case runner.(config) do
        {:ok, 0} ->
          if verbose?, do: Mix.shell().info("[verbose] exit: 0 (ok)")
          :ok

        {:ok, code} ->
          if verbose?, do: Mix.shell().info("[verbose] exit: #{code} (error)")
          {:error, {:nonzero_exit, stage.name, code}}

        {:error, reason} ->
          if verbose?, do: Mix.shell().info("[verbose] error: #{inspect(reason)}")
          {:error, {stage.name, reason}}
      end
    end
  end

  @doc false
  def parse_verdict(run_dir, verdict_base_name) do
    case Artifact.read(run_dir, verdict_base_name) do
      {:ok, content} ->
        first_line = content |> String.trim() |> String.split("\n") |> List.first("")
        if String.match?(first_line, ~r/^APPROVE/i), do: :approve, else: :reject

      {:error, _} ->
        # If we can't read the verdict, treat as approve to avoid infinite loops
        :approve
    end
  end
end
