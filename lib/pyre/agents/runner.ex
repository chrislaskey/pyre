defmodule Pyre.Agents.Runner do
  @moduledoc """
  LLM invocation abstraction. The ONLY module that knows about the `claude` CLI.

  To swap providers, change only this module.
  """

  @type config :: %{
          prompt: String.t(),
          system_prompt: String.t(),
          allowed_tools: [String.t()],
          model: String.t(),
          working_dir: String.t(),
          run_dir: String.t(),
          permission_mode: String.t()
        }

  @doc """
  Executes the claude CLI with the given configuration.

  Streams output to stdout so the user can see progress.
  Returns `{:ok, exit_code}` or `{:error, reason}`.
  """
  @spec run(config()) :: {:ok, non_neg_integer()} | {:error, term()}
  def run(config) do
    {_cmd, args} = build_command(config)

    try do
      {_output, exit_code} =
        System.cmd("claude", args,
          cd: config.working_dir,
          into: IO.stream(:stdio, :line),
          stderr_to_stdout: true,
          env: [{"CLAUDECODE", nil}]
        )

      {:ok, exit_code}
    rescue
      e in ErlangError -> {:error, e.original}
    end
  end

  @doc """
  Builds the command and argument list for the claude CLI.

  This function is pure and testable without executing anything.
  """
  @spec build_command(config()) :: {String.t(), [String.t()]}
  def build_command(config) do
    args =
      [
        "-p",
        config.prompt,
        "--append-system-prompt",
        config.system_prompt,
        "--allowedTools",
        Enum.join(config.allowed_tools, ","),
        "--model",
        config.model,
        "--permission-mode",
        config.permission_mode,
        "--add-dir",
        config.run_dir
      ]

    {"claude", args}
  end
end
