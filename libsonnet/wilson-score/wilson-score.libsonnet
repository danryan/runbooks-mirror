local strings = import 'utils/strings.libsonnet';

// Lookup from https://docs.google.com/spreadsheets/d/1Kpn7GZTJ280sRCbmC4T6bHixU1Q0biIH2DXhlskM2Mo/edit#gid=0
// https://www.statisticshowto.com/probability-and-statistics/find-critical-values/
local confidenceLookup =
  {
    '80%': 1.281551564,
    '85%': 1.439531472,
    '90%': 1.644853625,
    '95%': 1.959963986,
    '98%': 2.326347874,
    '99%': 2.575829306,
    '99.50%': 2.80703377,
    '99.95%': 3.4807564,
  };

local confidenceBoundaryExpression(isLowerBoundary, scoreRate, totalRate, windowInSeconds, confidence) =
  local z = std.get(confidenceLookup, confidence, error 'Unknown confidence value ' + confidence);

  local zSquared = z * z;

  // phat is a ratio in a Bernoulli trial process
  local phatExpression = '(%s / %s)' % [scoreRate, totalRate];

  // Convert from rate/second to total score over window period
  local scoreCountExpr = '(%s * %d)' % [scoreRate, windowInSeconds];
  local totalCountExpr = '(%s * %d)' % [totalRate, windowInSeconds];

  //  a = phat + z * z / (2 * total)
  local aExpr = |||
    (
      %(phatExpression)s
      +
      %(zSquared)f / (2 * %(totalCountExpr)s)
    )
  ||| % {
    phatExpression: strings.indent(phatExpression, 2),
    zSquared: zSquared,
    totalCountExpr: totalCountExpr,
  };

  // b = z * sqrt((phat * (1 - phat) + z * z / (4 * total)) / total);
  local bExpr =
    |||
      %(z)f
      *
      sqrt(
        (
          %(phatExpression)s * (1 - %(phatExpression)s)
          +
          %(zSquared)f / (4 * %(totalCountExpr)s)
        )
        /
        %(totalCountExpr)s
      )
    ||| % {
      phatExpression: phatExpression,
      z: z,
      zSquared: zSquared,
      totalCountExpr: totalCountExpr,
    };

  local cExpr =
    |||
      (1 + %(zSquared)f / %(totalCountExpr)s)
    ||| % {
      zSquared: zSquared,
      totalCountExpr: totalCountExpr,
    };

  local operator = if isLowerBoundary then '-' else '+';

  |||
    (
      %(aExpr)s
      %(operator)s
      %(bExpr)s
    )
    /
    %(cExpr)s
  ||| % {
    operator: operator,
    aExpr: strings.indent(aExpr, 2),
    bExpr: strings.indent(bExpr, 2),
    cExpr: cExpr,
  };

{
  /**
   * Given a score, total, window and confidence, produces a PromQL expression for the lower boundary
   * Wilson Score Interval
   */
  lower(scoreRate, totalRate, windowInSeconds, confidence):: confidenceBoundaryExpression(true, scoreRate, totalRate, windowInSeconds, confidence),

  /**
   * Given a score, total, window and confidence, produces a PromQL expression for the upper boundary
   * Wilson Score Interval
   */
  upper(scoreRate, totalRate, windowInSeconds, confidence):: confidenceBoundaryExpression(false, scoreRate, totalRate, windowInSeconds, confidence),
}