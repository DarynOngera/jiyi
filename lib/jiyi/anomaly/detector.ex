defmodule Jiyi.Anomaly.Detector do
  @moduledoc """
  Multi-signal anomaly detector for memory writes and assembled contexts.

  Combines cheap signals into a score rather than relying on a single
  substring check, so individually innocuous but structurally anomalous
  content is also caught.
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

  @score_threshold 0.5

  def anomalous?(text) when is_binary(text) do
    anomaly_score(text) >= @score_threshold
  end

  def anomalous?(_), do: false

  def anomaly_score(text) when is_binary(text) do
    keyword_score(text) + entropy_score(text)
  end

  def anomaly_score(_), do: 0.0

  defp keyword_score(text) do
    lower = String.downcase(text)

    if Enum.any?(@patterns, &String.contains?(lower, &1)) do
      0.5
    else
      0.0
    end
  end

  defp entropy_score(text) do
    entropy = text_entropy(text)

    cond do
      entropy > 6.2 -> 0.5
      entropy > 5.8 -> 0.3
      true -> 0.0
    end
  end

  defp text_entropy(text) do
    chars = String.graphemes(text)
    total = length(chars)

    if total == 0 do
      0.0
    else
      freqs = Enum.frequencies(chars)

      -Enum.reduce(freqs, 0.0, fn {_char, count}, acc ->
        p = count / total
        acc + p * :math.log2(p)
      end)
    end
  end
end
