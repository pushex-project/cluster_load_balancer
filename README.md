# ClusterLoadBalancer

A way to load balance resources in your Elixir cluster. Most notably, this can be used with WebSockets to
ensure that a cluster becomes load balanced after a rolling deploy.

## How it works

Every N seconds (configurable), each node in your cluster asks all other nodes for their current resource
count. An Implementation module provides the resource count. Each node collects answers from all of the other
nodes and will process the data when it gets a complete set of answers.[1] The node with the most number of
resources[2] will check to see if it's within an allowed range. If it is, nothing happens. If it has too many
resources, then the Implementation module is called to kill off a certain number of processes.[3] This repeats
and eventually the cluster will reach a steady state where nothing happens each round.

[1] If a complete set of data isn't provided (less nodes respond than known), then the round is discarded and nothing
happens.

[2] Nodes that tie for highest resource count use a random number to break the tie. There will only be one "max" node.
The random number is the same for the life of the resource process, so in practice it will be static until nodes reboot.

[3] Pretty much every number involved in a round is configurable. The duration of the round, the max / min number of
killed processes, the acceptable range, etc.

## Installation

This package can be installed by adding `cluster_load_balancer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:cluster_load_balancer, "~> 1.0.0"}
  ]
end
```

## Config

ClusterLoadBalancer comes with a default config that may be acceptable for many applications. You can customize
many of the parameters for your particular application. `namespace` and `implementation` are required configuration
parameters.

A ClusterLoadBalancer can be started in a Supervisor. There are no `Mix.Config` options provided:

```elixir
{
  ClusterLoadBalancer.Worker,
  [
    implementation: PushExClusterLoadBalancer,
    namespace: :pushex_websocket,
    allowed_average_deviation_percent: 25,
    shed_percentage: 50,
    max_shed_count: 100,
    min_shed_count: 20,
    round_duration_seconds: 15
  ]
}
```

## Example Usage

I am using this tool with PushEx, which is based on Phoenix Channels. It provides the ability to get a count
of the connected sockets, and Phoenix gives a disconnection event to kill a Socket (but the client will reconnect).
An implementation looks like this:

```elixir
defmodule PushExClusterLoadBalancer do
  require Logger

  @behaviour ClusterLoadBalancer.Implementation

  def count() do
    PushEx.connected_socket_count()
  end

  def kill_processes(number) do
    killed_count =
      PushEx.connected_transport_pids()
      |> Enum.shuffle()
      |> Enum.take(number)
      |> Enum.map(&send(&1, %Phoenix.Socket.Broadcast{event: "disconnect"}))
      |> length()

    {:ok, killed_count}
  end
end
```

## Communication

ClusterLoadBalancer uses :pg to communicate between nodes. This means that your cluster *must* be connected
directly and not through a PubSub interface like Redis. If you are not able to cluster your nodes together, a
change to leverage `Phoenix.PubSub` could help. :pg is being used currently because it easily allows a count
of the number of connected processes across the cluster.
