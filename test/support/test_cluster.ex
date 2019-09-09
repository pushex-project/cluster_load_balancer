defmodule TestCluster do
  require Logger

  def start_nodes(number) do
    Enum.each(1..number, fn index ->
      with_deadline(30_000, fn ->
        # create a slave node
        {:ok, node} = :slave.start_link(:localhost, 'slave_#{index}', '-env MIX_ENV test')
        add_code_paths(node)
        transfer_configuration(node)
        ensure_applications_started(node)
      end)
    end)

    [node() | Node.list()]
  end

  def disconnect(list) do
    Enum.map(list, &Node.disconnect(&1))
  end

  # If this doesn't work as expected then IO.inspect the output to find the error!
  def exec_ast(node, ast) do
    rpc(node, Code, :eval_quoted, [ast])
  end

  def setup_node_for_cluster_once() do
    :ok = :net_kernel.monitor_nodes(true)
    _ = :os.cmd('epmd -daemon')
    {:ok, _master} = Node.start(:master@localhost, :shortnames)
    :ok
  end

  # private

  defp rpc(node, module, function, args) do
    :rpc.block_call(node, module, function, args)
  end

  defp add_code_paths(node) do
    rpc(node, :code, :add_paths, [:code.get_path()])
  end

  defp transfer_configuration(node) do
    for {app_name, _, _} <- Application.loaded_applications() do
      for {key, val} <- Application.get_all_env(app_name) do
        :ok = rpc(node, Application, :put_env, [app_name, key, val])
      end
    end
  end

  defp ensure_applications_started(node) do
    ensure_logger_is_started_first(node)
    make_logger_have_configuration(node)

    for {app_name, _, _} <- Application.loaded_applications() do
      rpc(node, Application, :ensure_all_started, [app_name])
    end
  end

  defp ensure_logger_is_started_first(node) do
    rpc(node, Application, :ensure_all_started, [:mix])
    rpc(node, Application, :ensure_all_started, [:logger])
  end

  defp make_logger_have_configuration(node) do
    :ok = rpc(node, Elixir.Logger, :configure, [[level: Logger.level()]])
  end

  defp with_deadline(timeout, fun) do
    parent = self()
    ref = make_ref()

    pid =
      spawn_link(fn ->
        receive do
          ^ref -> :ok
        after
          timeout ->
            Logger.error("Deadline for starting slave node reached")
            Process.exit(parent, :kill)
        end
      end)

    try do
      fun.()
    after
      send(pid, ref)
    end
  end
end
