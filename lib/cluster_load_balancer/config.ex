defmodule ClusterLoadBalancer.Config do
  @moduledoc """
  Configuration for a ClusterLoadBalancer instance
  """

  @typedoc """
  * impl: ClusterLoadBalancer.Implementation.Behavior implementation module used to power the load balancer worker
  * allowed_average_deviation_percent: How far the highest count node can be above the average before it is load balanced
  * shed_percentage: The amount of percentage between the average and the highest count that will be shed
  * max_shed_count: The most that can be shed at one time. An amount above this will be reduced to it
  * min_shed_count: The minimum that can be shed at one time. An amount below this will *not* shed
  * round_duration_seconds: How long each round will last
  """
  @type t :: %__MODULE__{
          impl: any(),
          allowed_average_deviation_percent: non_neg_integer(),
          shed_percentage: non_neg_integer(),
          max_shed_count: non_neg_integer(),
          min_shed_count: non_neg_integer(),
          round_duration_seconds: non_neg_integer()
        }

  @enforce_keys [
    :impl,
    :allowed_average_deviation_percent,
    :shed_percentage,
    :max_shed_count,
    :min_shed_count,
    :round_duration_seconds
  ]
  defstruct @enforce_keys
end
