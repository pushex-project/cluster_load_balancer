defmodule ClusterLoadBalancer.Calculator do
  @moduledoc false

  require Logger

  alias ClusterLoadBalancer.{Collection, Config}

  @doc """
  Provides the number of processes that should be corrected by the load balancer. This value will be 0
  if the current node doesn't meet the criteria for shedding or if it would shed an amount less than
  the configured minimum.
  """
  def amount_to_correct_by(collection = %Collection{topic: {topic, namespace}}, config = %Config{}) do
    if should_shed?(collection, config) do
      shed_amount(collection, config)
    else
      Logger.debug("#{topic}.#{namespace} should_shed?=false")
      0
    end
  end

  @doc false
  def should_shed?(collection = %Collection{}, config = %Config{}) do
    highest_count? = Collection.self_has_highest_count?(collection)
    self_count = Collection.self_count(collection)
    average_count = Collection.average_count(collection)

    max_allowed_count = average_count + config.allowed_average_deviation_percent / 100 * average_count
    outside_allowed_deviation? = self_count > max_allowed_count

    {topic, namespace} = collection.topic
    Logger.debug("#{topic}.#{namespace} highest_count?=#{inspect(highest_count?)} avg=#{average_count} self=#{self_count} max_allowed_count=#{max_allowed_count}")

    highest_count? && outside_allowed_deviation?
  end

  @doc false
  def shed_amount(collection = %Collection{}, config = %Config{}) do
    self_count = Collection.self_count(collection)
    average_count = Collection.average_count(collection)

    calc_shed_amount = trunc((self_count - average_count) * (config.shed_percentage / 100))
    shed_amount = min(config.max_shed_count, calc_shed_amount)
    will_shed? = shed_amount >= config.min_shed_count

    {topic, namespace} = collection.topic
    Logger.debug(
      "#{topic}.#{namespace} highest=true shed_amount=#{shed_amount} [calc,min,max]=[#{calc_shed_amount}, #{config.min_shed_count}, #{config.max_shed_count}] will_shed=#{
        will_shed?
      }"
    )

    if will_shed? do
      shed_amount
    else
      0
    end
  end
end
