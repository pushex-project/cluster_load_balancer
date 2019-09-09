defmodule ClusterLoadBalancer.Implementation do
  @moduledoc """
  Behavior for implementing a ClusterLoadBalancer. You must provide a way to interact with the
  underlying resources that are being load balanced.
  """

  @callback count() :: number
  @callback kill_processes(number) :: {:ok, number}
end
