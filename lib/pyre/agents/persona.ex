defmodule Pyre.Agents.Persona do
  @moduledoc """
  Loads persona `.md` files and builds prompts for agent stages.
  """

  @doc """
  Loads a persona Markdown file by name.

  The name should be an atom matching the filename without extension
  (e.g., `:product_manager` loads `product_manager.md`).

  Looks first in the consuming project's `priv/pyre/personas/` directory,
  then falls back to the library's built-in personas.
  """
  @spec load(atom()) :: {:ok, String.t()} | {:error, term()}
  def load(persona_name) do
    path = Path.join(personas_dir(), "#{persona_name}.md")
    File.read(path)
  end

  defp personas_dir do
    project_dir = Path.join(File.cwd!(), "priv/pyre/personas")

    if File.dir?(project_dir) do
      project_dir
    else
      Application.app_dir(:pyre, "priv/pyre/personas")
    end
  end

  @doc """
  Builds the system prompt for a persona.

  Returns the persona's Markdown content to be used as the system prompt.
  """
  @spec build_system_prompt(atom()) :: {:ok, String.t()} | {:error, term()}
  def build_system_prompt(persona_name) do
    load(persona_name)
  end

  @doc """
  Builds the user prompt for an agent stage.

  Assembles the feature description, any artifacts from prior stages,
  and output instructions telling the agent where to write its artifact.

  ## Parameters

  - `feature_description` — The original feature request
  - `artifacts_content` — Pre-assembled content from prior artifacts (or empty string)
  - `run_dir` — Path to the current run directory
  - `artifact_filename` — The filename this agent should write its output to
  """
  @spec build_prompt(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def build_prompt(feature_description, artifacts_content, run_dir, artifact_filename) do
    sections = [
      "## Feature Request\n\n#{feature_description}"
    ]

    sections =
      if artifacts_content != "" do
        sections ++ ["## Prior Artifacts\n\n#{artifacts_content}"]
      else
        sections
      end

    output_path = Path.join(run_dir, artifact_filename)

    sections =
      sections ++
        [
          "## Output Instructions\n\nWrite your output to: `#{output_path}`\n\nUse the Write tool to create this file. The file should be a Markdown document following the format specified in your persona instructions."
        ]

    Enum.join(sections, "\n\n")
  end
end
