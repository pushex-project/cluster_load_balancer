defmodule ClusterLoadBalancer.WorkerTest do
  # Not async due to TestCluster usage
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias ClusterLoadBalancer.Worker

  defmodule FakeImplementation do
    @behaviour ClusterLoadBalancer.Implementation

    def count, do: 1337

    def kill_processes(count) do
      send(self(), {:kill_processes_mock, count})
      {:ok, count}
    end
  end

  describe "init/1" do
    test "a namespace/impl is required" do
      assert_raise(KeyError, "key :namespace not found in: []", fn ->
        Worker.init([])
      end)

      assert_raise(KeyError, "key :implementation not found in: [namespace: :test]", fn ->
        Worker.init(namespace: :test)
      end)
    end

    test "a default config is provided" do
      assert {:ok,
              %{
                config: %ClusterLoadBalancer.Config{
                  allowed_average_deviation_percent: 25,
                  impl: nil,
                  max_shed_count: 100,
                  min_shed_count: 10,
                  round_duration_seconds: 10,
                  shed_percentage: 50
                },
                rand: rand,
                tick: 0,
                tick_state: nil,
                topic: :"Elixir.ClusterLoadBalancer.Worker.test"
              }} = Worker.init(namespace: :test, implementation: nil)

      assert rand >= 0 && rand <= 1
    end

    test "the config can be customized" do
      assert {:ok,
              %{
                config: %ClusterLoadBalancer.Config{
                  allowed_average_deviation_percent: 1,
                  impl: 2,
                  max_shed_count: 3,
                  min_shed_count: 4,
                  round_duration_seconds: 5,
                  shed_percentage: 6
                },
                rand: rand,
                tick: 0,
                tick_state: nil,
                topic: :"Elixir.ClusterLoadBalancer.Worker.test"
              }} =
               Worker.init(
                 namespace: :test,
                 allowed_average_deviation_percent: 1,
                 implementation: 2,
                 max_shed_count: 3,
                 min_shed_count: 4,
                 round_duration_seconds: 5,
                 shed_percentage: 6
               )

      assert rand >= 0 && rand <= 1
    end

    test "a tick is scheduled for round_duration_seconds in the future" do
      assert {:ok, _} = Worker.init(namespace: :test, implementation: nil, round_duration_seconds: 0.1)
      assert_receive :tick, 150
    end
  end

  describe "handle_info tick" do
    test "tick requests cluster counts, inits a collection struct, broadcasts collection to all nodes" do
      # Start a cluster of 2 nodes and start workers on them (must be real)
      TestCluster.start_nodes(2)
      |> tl()
      |> Enum.with_index()
      |> Enum.each(fn {node, i} ->
        assert {pid, [{{:pid, ClusterLoadBalancer.WorkerTest}, pid}]} =
                 TestCluster.exec_ast(
                   node,
                   quote do
                     {:ok, pid} = Worker.start_link(namespace: :test, implementation: %{count: unquote(i)})
                     pid
                   end
                 )
      end)

      # Start our "worker" which is really just us faking it
      {:ok, orig_state} = Worker.init(namespace: :test, implementation: %{count: 1337}, round_duration_seconds: 0.1)

      # Initial tick which we'll "handle" now
      assert_receive :tick, 150

      # The tick adds tick_state with 2 expected results (2 connected nodes)
      assert {:noreply, state} = Worker.handle_info(:tick, orig_state)
      assert state.tick == 1

      assert state.tick_state == %ClusterLoadBalancer.Collection{
               collected: [],
               expected_results_count: 2,
               self_result: %ClusterLoadBalancer.Collection.Result{
                 count: 1337,
                 rand: state.rand,
                 tick: 1
               },
               tick: 1,
               topic: :"Elixir.ClusterLoadBalancer.Worker.test"
             }

      # Another tick is scheduled
      assert_receive :tick, 150

      # We receive replies from the nodes indicating that they were sent a collection request and responded with results
      assert_receive {:"$gen_cast", {:collect_result, %ClusterLoadBalancer.Collection.Result{count: 0, rand: _, tick: 1}}}, 1000
      assert_receive {:"$gen_cast", {:collect_result, %ClusterLoadBalancer.Collection.Result{count: 1, rand: _, tick: 1}}}, 1000
    end
  end

  describe "handle_cast collect_request" do
    test "the sending pid receives a response of the impl count function" do
      {:ok, state = %{rand: rand}} = Worker.init(namespace: :test, implementation: %{count: 1337})
      {:noreply, ^state} = Worker.handle_cast({:collect_request, 2, self()}, state)

      assert_receive {:"$gen_cast", {:collect_result, %ClusterLoadBalancer.Collection.Result{count: 1337, rand: ^rand, tick: 2}}}, 1000
    end
  end

  describe "handle_cast collect_result" do
    test "result.tick != state.tick logs an info because the round was too slow" do
      result = ClusterLoadBalancer.Collection.init_result(-1, 0, 0)
      {:ok, state} = Worker.init(namespace: :test, implementation: %{count: 1337})

      assert capture_log(fn ->
               assert {:noreply, ^state} = Worker.handle_cast({:collect_result, result}, state)
             end) =~ "Elixir.ClusterLoadBalancer.Worker.test collect_result delivered too slow"
    end

    test "result.tick == state.tick adds the result to the collection" do
      assert {:ok, state} = Worker.init(namespace: :test, implementation: %{count: 1337})
      assert {:noreply, state} = Worker.handle_info(:tick, state)
      state = Map.put(state, :tick_state, %{state.tick_state | expected_results_count: 2})
      result = ClusterLoadBalancer.Collection.init_result(1, 1000, 0)
      assert {:noreply, state} = Worker.handle_cast({:collect_result, result}, state)

      assert state.tick_state.collected == [result]
    end

    test "final result runs the correction code if this node requires it" do
      assert {:ok, state} = Worker.init(namespace: :test, implementation: FakeImplementation)
      assert {:noreply, state} = Worker.handle_info(:tick, state)
      state = Map.put(state, :tick_state, %{state.tick_state | expected_results_count: 2})
      result = ClusterLoadBalancer.Collection.init_result(1, 0, 0)
      assert {:noreply, state} = Worker.handle_cast({:collect_result, result}, state)

      assert capture_log(fn ->
               assert {:noreply, final_state} = Worker.handle_cast({:collect_result, result}, state)

               # The tick_state is finalized so was removed
               assert final_state.tick_state == nil
             end) =~ "[debug] Elixir.ClusterLoadBalancer.Worker.test round finalized with 3 participants, amount_to_correct_by=100"

      assert_receive {:kill_processes_mock, 100}
    end
  end
end
