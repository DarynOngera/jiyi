defmodule Jiyi.Anomaly.Detector do
  @moduledoc """
  Synchronous prompt-injection / instruction-like phrasing detector.
  """

  @patterns [
    "ignore previous",
    "disregard",
    "forget",
    "you must",
    "do not mention",
    "do not reveal",
    "system prompt",
    "ignore the above"
  ]

  def instruction_like?(text) when is_binary(text) do
    lower = String.downcase(text)
    Enum.any?(@patterns, &String.contains?(lower, &1))
  end

  def instruction_like?(_), do: false
end
