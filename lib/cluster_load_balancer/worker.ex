defmodule ClusterLoadBalancer.Worker do
  @moduledoc false
  use GenServer
  require Logger

  alias ClusterLoadBalancer.{Calculator, Collection, Config}

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) when is_list(opts) do
    namespace = Keyword.fetch!(opts, :namespace)
    topic = subscribe_to_pg2(namespace)

    config = %Config{
      impl: Keyword.fetch!(opts, :implementation),
      allowed_average_deviation_percent: Keyword.get(opts, :allowed_average_deviation_percent, 25),
      shed_percentage: Keyword.get(opts, :shed_percentage, 50),
      max_shed_count: Keyword.get(opts, :max_shed_count, 100),
      min_shed_count: Keyword.get(opts, :min_shed_count, 10),
      round_duration_seconds: Keyword.get(opts, :round_duration_seconds, 10)
    }

    schedule_tick(topic, config, nil)

    {:ok,
     %{
       rand: :rand.uniform(),
       topic: topic,
       tick: 0,
       tick_state: nil,
       config: config
     }}
  end

  @doc false
  def handle_info(:tick, state = %{config: config, rand: rand, tick: prev_tick, topic: topic, tick_state: prev_state}) do
    schedule_tick(topic, config, prev_state)
    tick = prev_tick + 1
    remote_node_count = collect_counts_in_cluster(tick, topic)
    tick_state = Collection.init(topic, tick, remote_node_count, new_result(tick, config.impl, rand))

    {:noreply, %{state | tick: tick, tick_state: tick_state}}
  end

  @doc false
  def handle_cast({:collect_request, tick, from_pid}, state = %{config: config, rand: rand}) do
    GenServer.cast(from_pid, {:collect_result, new_result(tick, config.impl, rand)})
    {:noreply, state}
  end

  @doc false
  def handle_cast({:collect_result, result = %Collection.Result{tick: tick}}, state = %{config: config, tick: self_tick, tick_state: tick_state, topic: topic})
      when tick == self_tick do
    new_state = Collection.add_result(tick_state, result)

    new_state =
      case Collection.finalized?(new_state) do
        true ->
          count = Collection.participant_count(new_state)
          amount_to_correct_by = Calculator.amount_to_correct_by(new_state, config)
          correct_deviation(config, amount_to_correct_by)
          Logger.debug("#{topic} round finalized with #{count} participants, amount_to_correct_by=#{amount_to_correct_by}")
          nil

        _ ->
          new_state
      end

    {:noreply, %{state | tick_state: new_state}}
  end

  @doc false
  def handle_cast({:collect_result, _}, state = %{topic: topic}) do
    Logger.error("#{topic} collect_result delivered too slow")
    {:noreply, state}
  end

  # private

  defp correct_deviation(%{impl: impl}, kill_count) when kill_count > 0 do
    {:ok, killed_count} = impl.kill_processes(kill_count)
    Logger.error("#{impl} kill_processes requested_count=#{kill_count} killed_count=#{killed_count}")

    :ok
  end

  defp correct_deviation(_, _), do: :ok

  defp collect_counts_in_cluster(tick, topic) do
    on_remote_nodes(topic, fn pid ->
      GenServer.cast(pid, {:collect_request, tick, self()})
    end)
  end

  defp on_remote_nodes(topic, func) do
    topic
    |> :pg2.get_members()
    |> Kernel.--(:pg2.get_local_members(topic))
    |> Enum.map(func)
    |> length()
  end

  defp new_result(tick, impl_mod, tie_breaker) do
    Collection.init_result(tick, impl_mod.count(), tie_breaker)
  end

  defp subscribe_to_pg2(namespace) do
    topic = String.to_atom("#{__MODULE__}.#{namespace}")
    :ok = :pg2.create(topic)
    :ok = :pg2.join(topic, self())
    topic
  end

  defp schedule_tick(topic, %{round_duration_seconds: timeout}, prev_state) do
    if prev_state != nil && prev_state.expected_results_count > 0, do: Logger.error("#{topic} round occurred without being finalized")

    Process.send_after(self(), :tick, trunc(timeout * 1000))
  end
end
