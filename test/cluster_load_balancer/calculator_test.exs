defmodule ClusterLoadBalancer.CalculatorTest do
  use ExUnit.Case, async: true

  alias ClusterLoadBalancer.{Calculator, Collection, Config}

  @config %Config{
    impl: nil,
    allowed_average_deviation_percent: 25,
    shed_percentage: 50,
    max_shed_count: 100,
    min_shed_count: 10,
    round_duration_seconds: nil
  }

  defp generate_self_collection(count) do
    Collection.init("test", nil, nil, Collection.init_result(nil, count, nil))
  end

  defp generate_multi_collection(self: {count, rand}, remotes: counts) when is_list(counts) do
    col = Collection.init("test", nil, nil, Collection.init_result(nil, count, rand))

    Enum.reduce(counts, col, fn {count, rand}, col ->
      Collection.add_result(col, Collection.init_result(nil, count, rand))
    end)
  end

  defp generate_multi_collection(self: count, remotes: counts) when is_list(counts) do
    col = Collection.init("test", nil, nil, Collection.init_result(nil, count, nil))

    Enum.reduce(counts, col, fn count, col ->
      Collection.add_result(col, Collection.init_result(nil, count, nil))
    end)
  end

  describe "private should_shed?" do
    test "a single node can never shed" do
      assert Calculator.should_shed?(generate_self_collection(0), @config) == false
      assert Calculator.should_shed?(generate_self_collection(100), @config) == false
      assert Calculator.should_shed?(generate_self_collection(100_000), @config) == false
    end

    test "the current node is the highest result, various allowed_average_deviation_percent" do
      # true ; avg = 50, allowed deviation = 62.5, self = 100
      assert Calculator.should_shed?(generate_multi_collection(self: 100, remotes: [0]), @config) == true

      # true ; avg = 79.5, allowed deviation = 99.375, self = 100
      assert Calculator.should_shed?(generate_multi_collection(self: 100, remotes: [59]), @config) == true

      # true ; avg = 4.333, allowed deviation = 5.41, self = 10
      assert Calculator.should_shed?(generate_multi_collection(self: 10, remotes: [1, 2]), @config) == true

      # false ; avg = 80, allowed deviation = 100, self = 100
      assert Calculator.should_shed?(generate_multi_collection(self: 100, remotes: [60]), @config) == false

      # false ; avg = 80.5, allowed deviation = 100.625, self = 100
      assert Calculator.should_shed?(generate_multi_collection(self: 100, remotes: [61]), @config) == false
    end

    test "the current node is not the highest result, various allowed_average_deviation_percent" do
      # avg = 50, allowed deviation = 62.5, self = 0
      assert Calculator.should_shed?(generate_multi_collection(self: 0, remotes: [100]), @config) == false

      # avg = 28.4, allowed deviation = 35.5, self = 99, normally outside deviation but isn't the largest
      assert Calculator.should_shed?(generate_multi_collection(self: 99, remotes: [100, 0, 0, 0, 0, 0]), @config) == false
    end

    test "ties to highest count are broken by rand" do
      assert Calculator.should_shed?(generate_multi_collection(self: {100, 0.25}, remotes: [{100, 0.26}, {0, 0}, {0, 0}]), @config) == false
      assert Calculator.should_shed?(generate_multi_collection(self: {100, 0.27}, remotes: [{100, 0.26}, {0, 0}, {0, 0}]), @config) == true

      # double ties are inprobable and the round skips without a highest
      assert Calculator.should_shed?(generate_multi_collection(self: {100, 0.26}, remotes: [{100, 0.26}, {0, 0}, {0, 0}]), @config) == false
    end
  end

  describe "private shed_amount" do
    test "the shed percentage of the average difference is shed" do
      # (100 - 50) * 0.5 = 25
      assert Calculator.shed_amount(generate_multi_collection(self: 100, remotes: [0]), @config) == 25

      # (100 - 50) * 1 = 50
      assert Calculator.shed_amount(generate_multi_collection(self: 100, remotes: [0]), %{@config | shed_percentage: 100}) == 50

      # (100 - 50) * 0.2 = 10
      assert Calculator.shed_amount(generate_multi_collection(self: 100, remotes: [0]), %{@config | shed_percentage: 20}) == 10
    end

    test "a shed amount lower than the minimum becomes 0, so that the system can become reasonably balanced" do
      # (100 - 50) * 0.18 = 9 < 10
      assert Calculator.shed_amount(generate_multi_collection(self: 100, remotes: [0]), %{@config | shed_percentage: 10}) == 0

      # (100 - 50) * 1 = 50 < 51
      assert Calculator.shed_amount(generate_multi_collection(self: 100, remotes: [0]), %{@config | shed_percentage: 100, min_shed_count: 51}) == 0
    end

    test "a shed amount higher than the maximum becomes the maximum" do
      # (100 - 50) * 0.5 = 25 > 10
      assert Calculator.shed_amount(generate_multi_collection(self: 100, remotes: [0]), %{@config | max_shed_count: 10}) == 10

      # (100 - 50) * 0.5 = 25 = 25
      assert Calculator.shed_amount(generate_multi_collection(self: 100, remotes: [0]), %{@config | max_shed_count: 25}) == 25

      # (100 - 50) * 0.5 = 25 > 24
      assert Calculator.shed_amount(generate_multi_collection(self: 100, remotes: [0]), %{@config | max_shed_count: 24}) == 24
    end
  end

  describe "amount_to_correct_by" do
    test "it is 0 if it shouldn't shed" do
      assert Calculator.amount_to_correct_by(generate_self_collection(0), @config) == 0
      assert Calculator.amount_to_correct_by(generate_multi_collection(self: 100, remotes: [61]), @config) == 0
    end

    test "it is the shed amount if it should shed" do
      assert Calculator.amount_to_correct_by(generate_multi_collection(self: 100, remotes: [0]), @config) == 25
      # Shouldn't shed, so 0
      assert Calculator.amount_to_correct_by(generate_multi_collection(self: 0, remotes: [100]), @config) == 0
    end
  end
end
