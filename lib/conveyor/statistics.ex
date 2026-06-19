defmodule Conveyor.Statistics do
  @moduledoc """
  Small dependency-free numerical statistics helpers.

  Provides exact Beta-Binomial (Clopper-Pearson) confidence intervals for a binomial
  proportion, used by live capability sampling to record `p_low`/`p_high` at a frozen
  confidence level (ADR-02). The interval is derived from the inverse regularized
  incomplete beta function, implemented with a Lanczos log-gamma, the Numerical-Recipes
  continued fraction for the incomplete beta, and bisection for the quantile.
  """

  @fpmin 1.0e-300
  @eps 3.0e-12
  @betacf_max_iterations 300
  @bisect_iterations 100

  # Lanczos approximation coefficients (g = 7), accurate to ~15 significant digits.
  @lanczos [
    0.99999999999980993,
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109526572012,
    9.9843695780195716e-6,
    1.5056327351493116e-7
  ]
  @lanczos_g 7

  @doc """
  Two-sided Clopper-Pearson (exact Beta-Binomial) confidence interval for `successes` out
  of `trials` at the given `confidence` (e.g. `0.95`).

  Returns `{p_low, p_high}` as floats in `[0.0, 1.0]`, with hard `0.0`/`1.0` at the
  boundaries (`successes == 0` and `successes == trials`). Returns `{0.0, 1.0}` when
  `trials == 0`.
  """
  @spec clopper_pearson_interval(non_neg_integer(), non_neg_integer(), float()) ::
          {float(), float()}
  def clopper_pearson_interval(successes, trials, confidence)
      when is_integer(successes) and is_integer(trials) and successes >= 0 and
             successes <= trials and is_number(confidence) and confidence > 0 and confidence < 1 do
    if trials == 0 do
      {0.0, 1.0}
    else
      alpha = 1.0 - confidence

      lower =
        if successes == 0,
          do: 0.0,
          else: beta_quantile(alpha / 2.0, successes, trials - successes + 1)

      upper =
        if successes == trials,
          do: 1.0,
          else: beta_quantile(1.0 - alpha / 2.0, successes + 1, trials - successes)

      {lower, upper}
    end
  end

  @doc """
  Regularized incomplete beta function `I_x(a, b)`, returning a value in `[0.0, 1.0]`.
  Monotonically increasing in `x`, which the quantile inversion relies on.
  """
  @spec regularized_incomplete_beta(float(), number(), number()) :: float()
  def regularized_incomplete_beta(x, a, b) when is_number(a) and is_number(b) and a > 0 and b > 0 do
    cond do
      x <= 0.0 ->
        0.0

      x >= 1.0 ->
        1.0

      true ->
        ln_factor =
          lgamma(a + b) - lgamma(a) - lgamma(b) + a * :math.log(x) + b * :math.log(1.0 - x)

        factor = :math.exp(ln_factor)

        if x < (a + 1.0) / (a + b + 2.0) do
          factor * betacf(x, a, b) / a
        else
          1.0 - factor * betacf(1.0 - x, b, a) / b
        end
    end
  end

  # Inverse of I_x(a, b) in x: find x such that I_x(a, b) == p. Bisection is robust because
  # I_x is monotonically increasing in x on [0, 1].
  defp beta_quantile(p, a, b) do
    cond do
      p <= 0.0 -> 0.0
      p >= 1.0 -> 1.0
      true -> bisect(p, a, b, 0.0, 1.0, @bisect_iterations)
    end
  end

  defp bisect(_p, _a, _b, lo, hi, 0), do: (lo + hi) / 2.0

  defp bisect(p, a, b, lo, hi, iterations) do
    mid = (lo + hi) / 2.0

    if regularized_incomplete_beta(mid, a, b) < p do
      bisect(p, a, b, mid, hi, iterations - 1)
    else
      bisect(p, a, b, lo, mid, iterations - 1)
    end
  end

  # Lentz's continued fraction for the incomplete beta (Numerical Recipes betacf).
  defp betacf(x, a, b) do
    qab = a + b
    qap = a + 1.0
    qam = a - 1.0
    d = 1.0 / clamp(1.0 - qab * x / qap)
    betacf_step(x, a, b, qab, qap, qam, 1.0, d, d, 1)
  end

  defp betacf_step(_x, _a, _b, _qab, _qap, _qam, _c, _d, h, m) when m > @betacf_max_iterations,
    do: h

  defp betacf_step(x, a, b, qab, qap, qam, c, d, h, m) do
    m2 = 2 * m

    even = m * (b - m) * x / ((qam + m2) * (a + m2))
    d_even = 1.0 / clamp(1.0 + even * d)
    c_even = clamp(1.0 + even / c)
    h_even = h * d_even * c_even

    odd = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
    d_odd = 1.0 / clamp(1.0 + odd * d_even)
    c_odd = clamp(1.0 + odd / c_even)
    delta = d_odd * c_odd
    h_odd = h_even * delta

    if abs(delta - 1.0) < @eps do
      h_odd
    else
      betacf_step(x, a, b, qab, qap, qam, c_odd, d_odd, h_odd, m + 1)
    end
  end

  defp clamp(value), do: if(abs(value) < @fpmin, do: @fpmin, else: value)

  # Lanczos approximation for log-gamma (with reflection for x < 0.5).
  defp lgamma(x) when x < 0.5 do
    :math.log(:math.pi() / :math.sin(:math.pi() * x)) - lgamma(1.0 - x)
  end

  defp lgamma(x) do
    x1 = x - 1.0
    [c0 | rest] = @lanczos

    series =
      rest
      |> Enum.with_index(1)
      |> Enum.reduce(c0, fn {coef, i}, acc -> acc + coef / (x1 + i) end)

    t = x1 + @lanczos_g + 0.5
    0.5 * :math.log(2.0 * :math.pi()) + (x1 + 0.5) * :math.log(t) - t + :math.log(series)
  end
end
