defmodule Pyre.Agents.RunnerTest do
  use ExUnit.Case, async: true

  alias Pyre.Agents.Runner

  describe "build_command/1" do
    test "builds correct command with all options" do
      config = %{
        prompt: "Implement the feature",
        system_prompt: "You are a programmer",
        allowed_tools: ["Read", "Write", "Edit", "Bash"],
        model: "opus",
        working_dir: "/path/to/project",
        run_dir: "/path/to/run/20240101_120000",
        permission_mode: "bypassPermissions"
      }

      {"claude", args} = Runner.build_command(config)

      assert "-p" in args
      assert "Implement the feature" in args
      assert "--append-system-prompt" in args
      assert "You are a programmer" in args
      assert "--allowedTools" in args
      assert "Read,Write,Edit,Bash" in args
      assert "--model" in args
      assert "opus" in args
      assert "--permission-mode" in args
      assert "bypassPermissions" in args
      assert "--add-dir" in args
      assert "/path/to/run/20240101_120000" in args
    end

    test "joins allowed tools with commas" do
      config = %{
        prompt: "test",
        system_prompt: "test",
        allowed_tools: ["Read", "Glob", "Grep", "Write"],
        model: "sonnet",
        working_dir: "/tmp",
        run_dir: "/tmp/run",
        permission_mode: "acceptEdits"
      }

      {"claude", args} = Runner.build_command(config)

      tools_index = Enum.find_index(args, &(&1 == "--allowedTools"))
      assert Enum.at(args, tools_index + 1) == "Read,Glob,Grep,Write"
    end

    test "uses sonnet model for non-coding stages" do
      config = %{
        prompt: "Define requirements",
        system_prompt: "You are a product manager",
        allowed_tools: ["Read", "Glob", "Grep", "Write"],
        model: "sonnet",
        working_dir: "/tmp",
        run_dir: "/tmp/run",
        permission_mode: "acceptEdits"
      }

      {"claude", args} = Runner.build_command(config)

      model_index = Enum.find_index(args, &(&1 == "--model"))
      assert Enum.at(args, model_index + 1) == "sonnet"
    end

    test "uses opus model for coding stages" do
      config = %{
        prompt: "Implement feature",
        system_prompt: "You are a programmer",
        allowed_tools: ["Read", "Write", "Edit", "Bash"],
        model: "opus",
        working_dir: "/tmp",
        run_dir: "/tmp/run",
        permission_mode: "bypassPermissions"
      }

      {"claude", args} = Runner.build_command(config)

      model_index = Enum.find_index(args, &(&1 == "--model"))
      assert Enum.at(args, model_index + 1) == "opus"
    end

    test "preserves argument order" do
      config = %{
        prompt: "test prompt",
        system_prompt: "system prompt",
        allowed_tools: ["Read"],
        model: "haiku",
        working_dir: "/tmp",
        run_dir: "/tmp/run",
        permission_mode: "acceptEdits"
      }

      {"claude", args} = Runner.build_command(config)

      # Verify the flags appear in the expected order
      assert ["-p", "test prompt" | _rest] = args
    end
  end
end
