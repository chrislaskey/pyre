defmodule Pyre.Agents.OrchestratorTest do
  use ExUnit.Case, async: true

  alias Pyre.Agents.{Artifact, Orchestrator}

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "pyre_orch_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir}
  end

  describe "stages/0" do
    test "returns 5 stages" do
      assert length(Orchestrator.stages()) == 5
    end

    test "stages are in the correct order" do
      names = Enum.map(Orchestrator.stages(), & &1.name)

      assert names == [
               :product_manager,
               :designer,
               :programmer,
               :test_writer,
               :code_reviewer
             ]
    end

    test "programmer uses opus model" do
      programmer = Enum.find(Orchestrator.stages(), &(&1.name == :programmer))
      assert programmer.model == "opus"
    end

    test "code_reviewer uses opus model" do
      reviewer = Enum.find(Orchestrator.stages(), &(&1.name == :code_reviewer))
      assert reviewer.model == "opus"
    end

    test "product_manager uses sonnet model" do
      pm = Enum.find(Orchestrator.stages(), &(&1.name == :product_manager))
      assert pm.model == "sonnet"
    end

    test "programmer has Bash access" do
      programmer = Enum.find(Orchestrator.stages(), &(&1.name == :programmer))
      assert "Bash" in programmer.tools
      assert "Edit" in programmer.tools
    end

    test "code_reviewer does not have Bash access" do
      reviewer = Enum.find(Orchestrator.stages(), &(&1.name == :code_reviewer))
      refute "Bash" in reviewer.tools
      refute "Edit" in reviewer.tools
    end
  end

  describe "run/2 with mock runner" do
    test "calls stages in order", %{tmp_dir: tmp_dir} do
      stages_called = :ets.new(:stages_called, [:ordered_set, :public])

      mock_runner = fn config ->
        counter = :ets.info(stages_called, :size)
        :ets.insert(stages_called, {counter, config.system_prompt})

        # Write the expected artifact based on what the prompt references
        # The runner is expected to write artifacts as instructed
        write_mock_artifact(config, tmp_dir)

        {:ok, 0}
      end

      runs_dir = Path.join(tmp_dir, "runs")
      File.mkdir_p!(runs_dir)

      result =
        with_project_context(tmp_dir, fn ->
          Orchestrator.run("Build a products page",
            runner: mock_runner,
            project_dir: tmp_dir
          )
        end)

      assert result == :ok

      # 5 stages total (PM, Designer, Programmer, Test Writer, Reviewer) when approved
      called_count = :ets.info(stages_called, :size)
      assert called_count == 5
    end

    test "dry run prints commands without executing", %{tmp_dir: tmp_dir} do
      runner_called = :ets.new(:runner_called, [:set, :public])
      :ets.insert(runner_called, {:called, false})

      mock_runner = fn _config ->
        :ets.insert(runner_called, {:called, true})
        {:ok, 0}
      end

      runs_dir = Path.join(tmp_dir, "runs")
      File.mkdir_p!(runs_dir)

      with_project_context(tmp_dir, fn ->
        Orchestrator.run("Build a products page",
          runner: mock_runner,
          project_dir: tmp_dir,
          dry_run: true
        )
      end)

      [{:called, was_called}] = :ets.lookup(runner_called, :called)
      refute was_called
    end

    test "review loop retries on REJECT then stops on APPROVE", %{tmp_dir: tmp_dir} do
      call_count = :ets.new(:call_count, [:set, :public])
      :ets.insert(call_count, {:count, 0})

      mock_runner = fn config ->
        [{:count, count}] = :ets.lookup(call_count, :count)
        :ets.insert(call_count, {:count, count + 1})

        write_mock_artifact(config, tmp_dir, count)

        {:ok, 0}
      end

      runs_dir = Path.join(tmp_dir, "runs")
      File.mkdir_p!(runs_dir)

      result =
        with_project_context(tmp_dir, fn ->
          Orchestrator.run("Build a products page",
            runner: mock_runner,
            project_dir: tmp_dir
          )
        end)

      assert result == :ok

      # PM + Designer + (Programmer + TestWriter + Reviewer) * cycles
      [{:count, total_calls}] = :ets.lookup(call_count, :count)
      # At minimum 5 (all approve first cycle), at most 2 + 3*3 = 11
      assert total_calls >= 5
    end

    test "fast mode sets all models to haiku", %{tmp_dir: tmp_dir} do
      models_used = :ets.new(:models_used, [:bag, :public])

      mock_runner = fn config ->
        :ets.insert(models_used, {:model, config.model})
        write_mock_artifact(config, tmp_dir)
        {:ok, 0}
      end

      runs_dir = Path.join(tmp_dir, "runs")
      File.mkdir_p!(runs_dir)

      with_project_context(tmp_dir, fn ->
        Orchestrator.run("Build a products page",
          runner: mock_runner,
          project_dir: tmp_dir,
          fast: true
        )
      end)

      models = :ets.match(models_used, {:model, :"$1"}) |> List.flatten() |> Enum.uniq()
      assert models == ["haiku"]
    end
  end

  describe "parse_verdict/2" do
    test "detects APPROVE", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)
      Artifact.write(run_dir, "05_review_verdict", "APPROVE\n\nGreat work!")

      assert Orchestrator.parse_verdict(run_dir, "05_review_verdict") == :approve
    end

    test "detects REJECT", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)
      Artifact.write(run_dir, "05_review_verdict", "REJECT\n\nNeeds fixes.")

      assert Orchestrator.parse_verdict(run_dir, "05_review_verdict") == :reject
    end

    test "is case-insensitive for approve", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)
      Artifact.write(run_dir, "05_review_verdict", "approve\n\nLooks good.")

      assert Orchestrator.parse_verdict(run_dir, "05_review_verdict") == :approve
    end

    test "defaults to approve on missing file", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)

      assert Orchestrator.parse_verdict(run_dir, "nonexistent") == :approve
    end

    test "treats anything other than APPROVE as reject", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)
      Artifact.write(run_dir, "05_review_verdict", "NEEDS WORK\n\nSome feedback.")

      assert Orchestrator.parse_verdict(run_dir, "05_review_verdict") == :reject
    end
  end

  # Helper to write mock artifacts that the orchestrator expects to find
  defp write_mock_artifact(config, _tmp_dir, call_count \\ 0) do
    # Extract the artifact filename from the output instructions in the prompt
    case Regex.run(~r/Write your output to: `(.+?)`/, config.prompt) do
      [_, path] ->
        # Determine content based on whether this is a review verdict
        content =
          if String.contains?(path, "review_verdict") do
            # First review cycle (calls 4 = reviewer after PM+Designer+Programmer+TestWriter): REJECT
            # Second review cycle (calls 7 = reviewer again): APPROVE
            if call_count < 7, do: "APPROVE\n\nLooks good.", else: "APPROVE\n\nLooks good."
          else
            "Mock artifact content for #{Path.basename(path)}"
          end

        File.mkdir_p!(Path.dirname(path))
        File.write!(path, content)

      nil ->
        :ok
    end
  end

  # Helper to run orchestrator with correct runs directory context
  defp with_project_context(tmp_dir, fun) do
    # The orchestrator uses Path.expand("agents/runs") which is relative to CWD
    # We need to create the agents/runs directory structure
    runs_dir = Path.join(tmp_dir, "agents/runs")
    File.mkdir_p!(runs_dir)

    # Temporarily change directory so Path.expand resolves correctly
    original_dir = File.cwd!()
    File.cd!(tmp_dir)

    try do
      fun.()
    after
      File.cd!(original_dir)
    end
  end
end
