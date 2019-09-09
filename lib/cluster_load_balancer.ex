defmodule ClusterLoadBalancer do
  @moduledoc """
  ClusterLoadBalancer monitors for discrepancies in resource count across a cluster
  and kills processes on the current node if it's the maximum node and falls outside of
  an allowed deviation.

  You could use this to load balance any resource, although WebSockets or persistent HTTP
  connections are the most obvious use cases.

  All of the values are configurable to either allow the cluster to be more loosely
  load balanced or to be more tightly controlled.

  An assumption is made that a killed resource will recreate itself once killed (or your
  implementation has to handle that). Phoenix Channels, the primary use case for this,
  involve the client reconnecting when disconnected. This means that the connections
  will restart, but in a load balanced way.
  """

  alias __MODULE__.{Worker}

  def child_spec(opts) do
    %{
      id: Worker,
      start: {Worker, :start_link, [opts]}
    }
  end
end
