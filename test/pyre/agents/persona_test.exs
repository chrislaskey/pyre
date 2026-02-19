defmodule Pyre.Agents.PersonaTest do
  use ExUnit.Case, async: true

  alias Pyre.Agents.Persona

  @personas [:product_manager, :designer, :programmer, :test_writer, :code_reviewer]

  describe "load/1" do
    for persona <- @personas do
      test "loads #{persona} persona file" do
        {:ok, content} = Persona.load(unquote(persona))

        assert is_binary(content)
        assert String.length(content) > 0
        assert content =~ "#"
      end
    end

    test "returns error for nonexistent persona" do
      assert {:error, :enoent} = Persona.load(:nonexistent_persona)
    end
  end

  describe "build_system_prompt/1" do
    test "returns persona content as system prompt" do
      {:ok, system_prompt} = Persona.build_system_prompt(:product_manager)

      assert system_prompt =~ "Product Manager"
    end
  end

  describe "build_prompt/4" do
    test "includes feature description" do
      prompt = Persona.build_prompt("Build a products page", "", "/tmp/run", "01_requirements.md")

      assert prompt =~ "## Feature Request"
      assert prompt =~ "Build a products page"
    end

    test "includes artifacts content when provided" do
      artifacts = "## 01_requirements.md\n\nSome requirements"

      prompt =
        Persona.build_prompt("Build a products page", artifacts, "/tmp/run", "02_design_spec.md")

      assert prompt =~ "## Prior Artifacts"
      assert prompt =~ "Some requirements"
    end

    test "omits artifacts section when content is empty" do
      prompt = Persona.build_prompt("Build a products page", "", "/tmp/run", "01_requirements.md")

      refute prompt =~ "## Prior Artifacts"
    end

    test "includes output instructions with file path" do
      prompt =
        Persona.build_prompt(
          "Build a products page",
          "",
          "/tmp/run/20240101_120000",
          "01_requirements.md"
        )

      assert prompt =~ "## Output Instructions"
      assert prompt =~ "/tmp/run/20240101_120000/01_requirements.md"
      assert prompt =~ "Write tool"
    end
  end
end
