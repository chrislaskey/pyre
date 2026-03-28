defmodule Pyre.ConfigTest do
  use ExUnit.Case, async: false

  alias Pyre.Config
  alias Pyre.Events.FlowStarted

  defmodule TrackingConfig do
    use Pyre.Config

    @impl true
    def after_flow_start(event) do
      send(Process.get(:test_pid), {:hook, :after_flow_start, event})
      :ok
    end
  end

  defmodule CrashingConfig do
    use Pyre.Config

    @impl true
    def after_flow_start(_event) do
      raise "boom"
    end
  end

  setup do
    original = Application.get_env(:pyre, :config)
    on_exit(fn -> Application.put_env(:pyre, :config, original) end)
    :ok
  end

  describe "notify/2" do
    test "dispatches to default no-op without error" do
      Application.delete_env(:pyre, :config)

      assert :ok =
               Config.notify(:after_flow_start, %FlowStarted{
                 flow_module: Pyre.Flows.Task,
                 description: "test",
                 run_dir: "/tmp/test",
                 working_dir: "/tmp"
               })
    end

    test "dispatches to configured custom module" do
      Process.put(:test_pid, self())
      Application.put_env(:pyre, :config, TrackingConfig)

      event = %FlowStarted{
        flow_module: Pyre.Flows.Task,
        description: "test",
        run_dir: "/tmp/test",
        working_dir: "/tmp"
      }

      Config.notify(:after_flow_start, event)

      assert_received {:hook, :after_flow_start, ^event}
    end

    test "rescues exceptions in user hook implementations" do
      Application.put_env(:pyre, :config, CrashingConfig)

      assert :ok =
               Config.notify(:after_flow_start, %FlowStarted{
                 flow_module: Pyre.Flows.Task,
                 description: "test",
                 run_dir: "/tmp/test",
                 working_dir: "/tmp"
               })
    end
  end

  describe "__using__" do
    test "produces overridable callbacks" do
      # TrackingConfig overrides after_flow_start but inherits others
      assert function_exported?(TrackingConfig, :after_flow_start, 1)
      assert function_exported?(TrackingConfig, :after_flow_complete, 1)
      assert function_exported?(TrackingConfig, :after_flow_error, 1)
      assert function_exported?(TrackingConfig, :after_action_start, 1)
      assert function_exported?(TrackingConfig, :after_action_complete, 1)
      assert function_exported?(TrackingConfig, :after_action_error, 1)
      assert function_exported?(TrackingConfig, :after_llm_call_complete, 1)
      assert function_exported?(TrackingConfig, :after_llm_call_error, 1)
    end
  end
end
