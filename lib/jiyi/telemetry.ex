defmodule Jiyi.Telemetry do
  @moduledoc """
  Telemetry event definitions and a default logging handler.
  """

  @events [
    [:jiyi, :memory, :write],
    [:jiyi, :memory, :read],
    [:jiyi, :memory, :duplicate],
    [:jiyi, :memory, :quarantined],
    [:jiyi, :session, :crash],
    [:jiyi, :session, :restart],
    [:jiyi, :retrieval, :stage],
    [:jiyi, :circuit_breaker, :state_change]
  ]

  def attach_default_handler do
    :telemetry.attach_many(
      "jiyi-default-logger",
      @events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event(event, measurements, metadata, _config) do
    require Logger

    Logger.debug(
      "telemetry event=#{inspect(event)} measurements=#{inspect(measurements)} metadata=#{inspect(metadata)}"
    )
  end

  def events, do: @events
end
