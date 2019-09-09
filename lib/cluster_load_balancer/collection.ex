defmodule ClusterLoadBalancer.Collection do
  @moduledoc false

  defmodule Result do
    @moduledoc false

    @enforce_keys [:tick, :count, :rand]
    defstruct @enforce_keys
  end

  @enforce_keys [:expected_results_count, :self_result, :tick, :topic]
  defstruct @enforce_keys ++ [collected: []]

  def init(topic, tick, node_count, self_result = %Result{}) do
    %__MODULE__{expected_results_count: node_count, self_result: self_result, tick: tick, topic: topic}
  end

  def init_result(tick, count, rand) do
    %Result{tick: tick, count: count, rand: rand}
  end

  def add_result(state = %__MODULE__{collected: collected, tick: state_tick}, result = %Result{tick: tick}) when state_tick == tick do
    new_collected = [result | collected]
    %{state | collected: new_collected}
  end

  def add_result(state, _), do: state

  def finalized?(%{expected_results_count: expected_count, collected: collected}) do
    length(collected) == expected_count
  end

  def participant_count(%{expected_results_count: count}), do: count + 1

  def self_has_highest_count?(%{self_result: self, collected: collected}) do
    Enum.all?(collected, fn other ->
      self.count > other.count || (self.count == other.count && self.rand > other.rand)
    end)
  end

  def self_count(%{self_result: self}) do
    self.count
  end

  def average_count(%{self_result: self, collected: collected}) do
    collected
    |> Enum.map(& &1.count)
    |> Enum.sum()
    |> Kernel.+(self.count)
    |> Kernel./(length(collected) + 1)
  end
end
