defmodule Pyre.Agents.ArtifactTest do
  use ExUnit.Case, async: true

  alias Pyre.Agents.Artifact

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "pyre_artifact_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir}
  end

  describe "create_run_dir/1" do
    test "creates a timestamped directory", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)

      assert File.dir?(run_dir)
      dirname = Path.basename(run_dir)
      assert Regex.match?(~r/^\d{8}_\d{6}$/, dirname)
    end
  end

  describe "write/3 and read/2" do
    test "round-trips content", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)

      :ok = Artifact.write(run_dir, "01_requirements", "# Requirements\n\nSome content")
      {:ok, content} = Artifact.read(run_dir, "01_requirements")

      assert content == "# Requirements\n\nSome content"
    end

    test "handles .md extension in filename", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)

      :ok = Artifact.write(run_dir, "01_requirements.md", "content")
      {:ok, content} = Artifact.read(run_dir, "01_requirements.md")

      assert content == "content"
    end

    test "returns error for missing file", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)

      assert {:error, :enoent} = Artifact.read(run_dir, "nonexistent")
    end
  end

  describe "latest/2" do
    test "returns the only version", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)
      :ok = Artifact.write(run_dir, "03_implementation_summary", "v1 content")

      {:ok, filename, content} = Artifact.latest(run_dir, "03_implementation_summary")

      assert filename == "03_implementation_summary.md"
      assert content == "v1 content"
    end

    test "returns the highest versioned file", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)
      :ok = Artifact.write(run_dir, "03_implementation_summary", "v1 content")
      :ok = Artifact.write(run_dir, "03_implementation_summary_v2", "v2 content")
      :ok = Artifact.write(run_dir, "03_implementation_summary_v3", "v3 content")

      {:ok, filename, content} = Artifact.latest(run_dir, "03_implementation_summary")

      assert filename == "03_implementation_summary_v3.md"
      assert content == "v3 content"
    end

    test "handles .md extension in base name", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)
      :ok = Artifact.write(run_dir, "01_requirements", "content")

      {:ok, _filename, content} = Artifact.latest(run_dir, "01_requirements.md")
      assert content == "content"
    end

    test "returns error when no files match", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)

      assert {:error, :not_found} = Artifact.latest(run_dir, "nonexistent")
    end
  end

  describe "assemble/2" do
    test "concatenates multiple artifacts with headers", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)
      :ok = Artifact.write(run_dir, "01_requirements", "Requirements content")
      :ok = Artifact.write(run_dir, "02_design_spec", "Design content")

      {:ok, assembled} = Artifact.assemble(run_dir, ["01_requirements.md", "02_design_spec.md"])

      assert assembled =~ "## 01_requirements.md"
      assert assembled =~ "Requirements content"
      assert assembled =~ "---"
      assert assembled =~ "## 02_design_spec.md"
      assert assembled =~ "Design content"
    end

    test "returns empty string for empty list", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)

      assert {:ok, ""} = Artifact.assemble(run_dir, [])
    end

    test "resolves to latest version", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)
      :ok = Artifact.write(run_dir, "03_implementation_summary", "v1")
      :ok = Artifact.write(run_dir, "03_implementation_summary_v2", "v2")

      {:ok, assembled} = Artifact.assemble(run_dir, ["03_implementation_summary.md"])

      assert assembled =~ "03_implementation_summary_v2.md"
      assert assembled =~ "v2"
    end

    test "handles missing files gracefully", %{tmp_dir: tmp_dir} do
      {:ok, run_dir} = Artifact.create_run_dir(tmp_dir)

      {:ok, assembled} = Artifact.assemble(run_dir, ["missing.md"])

      assert assembled =~ "(not found)"
    end
  end

  describe "versioned_name/2" do
    test "returns base name for cycle 1" do
      assert Artifact.versioned_name("03_implementation_summary", 1) == "03_implementation_summary"
    end

    test "appends _v2 for cycle 2" do
      assert Artifact.versioned_name("03_implementation_summary", 2) == "03_implementation_summary_v2"
    end

    test "appends _v3 for cycle 3" do
      assert Artifact.versioned_name("03_implementation_summary", 3) == "03_implementation_summary_v3"
    end
  end
end
