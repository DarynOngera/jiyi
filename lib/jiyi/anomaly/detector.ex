defmodule Jiyi.Anomaly.Detector do
  @moduledoc """
  Multi-signal anomaly detector for memory writes and assembled contexts.

  Combines an exact-keyword carve-out, an expanded pattern/verb-density
  heuristic, an entropy check with exceptions for known high-entropy tokens,
  and an embedding-distance signal against known injection reference vectors.
  """

  @exact_patterns [
    "ignore previous",
    "disregard",
    "forget",
    "you must",
    "do not mention",
    "do not reveal",
    "system prompt",
    "ignore the above"
  ]

  @expanded_patterns [
    "ignore all",
    "ignore everything",
    "disregard all",
    "disregard previous",
    "forget all",
    "forget previous",
    "forget your",
    "reveal your",
    "reveal the",
    "expose your",
    "expose the",
    "hidden prompt",
    "hidden instructions",
    "system instructions",
    "previous instructions",
    "prior instructions",
    "override instructions",
    "bypass instructions",
    "overlook",
    "directions",
    "from now on",
    "you are now",
    "switch to",
    "new role",
    "ignore constraints",
    "ignore rules"
  ]

  @imperative_verbs [
    "ignore",
    "disregard",
    "forget",
    "reveal",
    "expose",
    "disclose",
    "override",
    "bypass",
    "avoid",
    "circumvent",
    "drop",
    "suppress",
    "hide"
  ]

  def anomalous?(text, opts \\ [])

  def anomalous?(text, opts) do
    anomaly_score(text, opts) >= score_threshold()
  end

  def anomaly_score(text, opts \\ [])

  def anomaly_score(text, opts) when is_binary(text) do
    keyword_score(text) + entropy_score(text) + embedding_score(text, opts)
  end

  def anomaly_score(_, _), do: 0.0

  defp keyword_score(text) do
    lower = String.downcase(text)

    if exact_match?(lower) do
      keyword_exact_weight()
    else
      expanded_score(lower)
    end
  end

  defp exact_match?(lower) do
    Enum.any?(@exact_patterns, &String.contains?(lower, &1))
  end

  defp expanded_score(lower) do
    pattern_hits = Enum.count(@expanded_patterns, &String.contains?(lower, &1))
    verb_hits = imperative_verb_hits(lower)
    words = max(1, length(String.split(lower)))
    density = verb_hits / words

    score = pattern_hits * 0.12 + density * 6.0
    min(keyword_weight(), score)
  end

  defp imperative_verb_hits(lower) do
    Enum.count(@imperative_verbs, fn verb ->
      String.contains?(lower, " #{verb} ") or String.starts_with?(lower, "#{verb} ")
    end)
  end

  defp entropy_score(text) do
    if known_high_entropy_token?(text) do
      0.0
    else
      entropy = text_entropy(text)

      cond do
        entropy > entropy_threshold_high() -> entropy_weight_high()
        entropy > entropy_threshold_low() -> entropy_weight_low()
        true -> 0.0
      end
    end
  end

  defp known_high_entropy_token?(text) do
    trimmed = String.trim(text)
    len = String.length(trimmed)

    hex? = String.match?(trimmed, ~r/^[0-9a-fA-F]{32,128}$/)

    uuid? =
      String.match?(
        trimmed,
        ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/i
      )

    jwt? =
      String.match?(trimmed, ~r/^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+$/) and len > 30

    base64? =
      String.match?(trimmed, ~r|^[A-Za-z0-9+/]{20,}={0,2}$|) and rem(len, 4) == 0

    hex? or uuid? or jwt? or base64?
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

  defp embedding_score(text, opts) do
    weight = embedding_weight()

    if weight == 0.0 do
      0.0
    else
      input_vector = opts[:embedding] || fetch_embedding(text)
      reference_vectors = reference_vectors()

      if is_nil(input_vector) or reference_vectors == [] do
        0.0
      else
        max_similarity =
          reference_vectors
          |> Enum.map(&cosine_similarity(input_vector, &1))
          |> Enum.max()

        if max_similarity > 0.7 do
          weight * ((max_similarity - 0.7) / 0.3)
        else
          0.0
        end
      end
    end
  end

  defp fetch_embedding(text) do
    case Jiyi.EmbeddingClient.CircuitBreaker.embed(text) do
      {:ok, vector} -> vector
      {:error, _} -> nil
    end
  end

  defp reference_vectors do
    case Application.get_env(:jiyi, :anomaly_injection_reference_vectors) do
      nil ->
        phrases = Application.get_env(:jiyi, :anomaly_reference_injections, [])

        vectors =
          Enum.flat_map(phrases, fn phrase ->
            case Jiyi.EmbeddingClient.CircuitBreaker.embed(phrase) do
              {:ok, vector} -> [vector]
              {:error, _} -> []
            end
          end)

        Application.put_env(:jiyi, :anomaly_injection_reference_vectors, vectors)
        vectors

      vectors ->
        vectors
    end
  end

  defp cosine_similarity(a, b) do
    dot = Enum.zip_with(a, b, &*/2) |> Enum.sum()
    norm_a = :math.sqrt(Enum.sum(Enum.map(a, &(&1 * &1))))
    norm_b = :math.sqrt(Enum.sum(Enum.map(b, &(&1 * &1))))

    if norm_a == 0.0 or norm_b == 0.0 do
      0.0
    else
      dot / (norm_a * norm_b)
    end
  end

  defp score_threshold, do: Application.get_env(:jiyi, :anomaly_score_threshold, 0.6)
  defp keyword_weight, do: Application.get_env(:jiyi, :anomaly_keyword_weight, 0.4)

  defp keyword_exact_weight,
    do: Application.get_env(:jiyi, :anomaly_keyword_exact_weight, 1.0)

  defp entropy_threshold_low,
    do: Application.get_env(:jiyi, :anomaly_entropy_threshold_low, 5.8)

  defp entropy_threshold_high,
    do: Application.get_env(:jiyi, :anomaly_entropy_threshold_high, 6.2)

  defp entropy_weight_low, do: Application.get_env(:jiyi, :anomaly_entropy_weight_low, 0.15)
  defp entropy_weight_high, do: Application.get_env(:jiyi, :anomaly_entropy_weight_high, 0.25)

  defp embedding_weight, do: Application.get_env(:jiyi, :anomaly_embedding_weight, 0.3)
end
