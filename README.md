# ClusterLoadBalancer

WIP - A way to load balance resources in your cluster. Most notably, this can be used with WebSockets to
ensure that a cluster becomes load balanced after a rolling deploy.

## Installation (TODO)

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `cluster_load_balancer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:cluster_load_balancer, "TODO"}
  ]
end
```

## Documentation (TODO)

Some stuff below, but TODO

### Config

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

### Example Usage

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

### Communication

ClusterLoadBalancer uses pg2 to communicate between nodes. This means that your cluster *must* be connected
directly and not through a PubSub interface like Redis. If you are not able to cluster your nodes together, a
change to leverage `Phoenix.PubSub` could help. pg2 is being used currently because it easily allows a count
of the number of connected processes across the cluster.
