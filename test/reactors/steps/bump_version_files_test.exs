defmodule Deploy.Reactors.Steps.BumpVersionFilesTest do
  use ExUnit.Case, async: true

  alias Deploy.Reactors.Steps.BumpVersionFiles

  setup do
    # Create a temporary workspace with version files
    workspace = Path.join(System.tmp_dir!(), "bump_version_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(workspace)
    File.mkdir_p!(Path.join(workspace, "backend"))
    File.mkdir_p!(Path.join(workspace, "frontend"))

    # Write initial version files
    File.write!(Path.join(workspace, "version.txt"), "2.4.10")
    File.write!(Path.join(workspace, "backend/version.txt"), "2.4.10")
    File.write!(Path.join(workspace, "frontend/package.json"), ~s|{"name": "app", "version": "2.4.10"}|)

    on_exit(fn -> File.rm_rf!(workspace) end)

    %{workspace: workspace}
  end

  describe "increment_patch/1" do
    test "increments patch version" do
      assert BumpVersionFiles.increment_patch("2.4.10") == "2.4.11"
    end

    test "handles version with leading/trailing whitespace" do
      assert BumpVersionFiles.increment_patch("  1.0.0\n") == "1.0.1"
    end

    test "increments from zero" do
      assert BumpVersionFiles.increment_patch("0.0.0") == "0.0.1"
    end
  end

  describe "run/3" do
    test "bumps version in all files", %{workspace: workspace} do
      args = %{workspace: workspace}

      assert {:ok, %{old_version: "2.4.10", new_version: "2.4.11"}} =
               BumpVersionFiles.run(args, %{}, [])

      # Verify version.txt
      assert File.read!(Path.join(workspace, "version.txt")) == "2.4.11"

      # Verify backend/version.txt
      assert File.read!(Path.join(workspace, "backend/version.txt")) == "2.4.11"

      # Verify frontend/package.json
      package_json = File.read!(Path.join(workspace, "frontend/package.json"))
      assert {:ok, decoded} = Jason.decode(package_json)
      assert decoded["version"] == "2.4.11"
      assert decoded["name"] == "app"  # Other fields preserved
    end

    test "returns error when version.txt missing", %{workspace: workspace} do
      File.rm!(Path.join(workspace, "version.txt"))

      args = %{workspace: workspace}
      assert {:error, msg} = BumpVersionFiles.run(args, %{}, [])
      assert msg =~ "Failed to read version file"
    end

    test "returns error when package.json has invalid JSON", %{workspace: workspace} do
      File.write!(Path.join(workspace, "frontend/package.json"), "not json")

      args = %{workspace: workspace}
      assert {:error, msg} = BumpVersionFiles.run(args, %{}, [])
      assert msg =~ "Failed to parse package.json"
    end
  end

  describe "compensate/4" do
    test "restores original version in all files", %{workspace: workspace} do
      # First bump the version
      args = %{workspace: workspace}
      {:ok, result} = BumpVersionFiles.run(args, %{}, [])

      # Verify it was bumped
      assert File.read!(Path.join(workspace, "version.txt")) == "2.4.11"

      # Now compensate
      assert :ok = BumpVersionFiles.compensate(result, args, %{}, [])

      # Verify restored
      assert File.read!(Path.join(workspace, "version.txt")) == "2.4.10"
      assert File.read!(Path.join(workspace, "backend/version.txt")) == "2.4.10"

      package_json = File.read!(Path.join(workspace, "frontend/package.json"))
      {:ok, decoded} = Jason.decode(package_json)
      assert decoded["version"] == "2.4.10"
    end
  end
end
