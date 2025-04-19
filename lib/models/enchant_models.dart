class EnchantResult {
  final int enchantLevel;
  final int bestStoneLevel;
  final double expectedCostForLevel;
  final double cumulativeExpectedCost;
  final int expectedStonesNeeded;
  final int cumulativeStones;
  final double successRate;
  final double supplement;

  EnchantResult({
    required this.enchantLevel,
    required this.bestStoneLevel,
    required this.expectedCostForLevel,
    required this.cumulativeExpectedCost,
    this.expectedStonesNeeded = 0,
    this.cumulativeStones = 0,
    this.successRate = 0.0,
    this.supplement = 0.0,
  });
}

class IndividualStoneCalcResult {
  final double successRatePlus0;
  final double successRatePlus10;
  final double stonesToPlus10;
  final double costToPlus10;
  final double stonesPlus10To15;
  final double costPlus10To15;
  final bool possibleTo10;
  final bool possibleTo15;

  IndividualStoneCalcResult({
    this.successRatePlus0 = 0.0,
    this.successRatePlus10 = 0.0,
    this.stonesToPlus10 = double.infinity,
    this.costToPlus10 = double.infinity,
    this.stonesPlus10To15 = double.infinity,
    this.costPlus10To15 = double.infinity,
    this.possibleTo10 = false,
    this.possibleTo15 = false,
  });

  IndividualStoneCalcResult copyWithCosts({
    required double newCostToPlus10,
    required double newCostPlus10To15,
  }) {
    return IndividualStoneCalcResult(
      successRatePlus0: successRatePlus0,
      successRatePlus10: successRatePlus10,
      stonesToPlus10: stonesToPlus10,
      costToPlus10: newCostToPlus10,
      stonesPlus10To15: stonesPlus10To15,
      costPlus10To15: newCostPlus10To15,
      possibleTo10: possibleTo10,
      possibleTo15: possibleTo15,
    );
  }
}

class OptimalCalculationResult {
  final List<EnchantResult> resultsToTarget; // Full range
  final Map<int, double> optimalExpectedCostPerLevel;
  final Map<int, double> optimalExpectedStonesPerLevel;
  final Map<int, Map<String, double>> optimalStoneUsageSummary; // Full range summary
  final Map<int, Map<int, double>>? optimalStonesBreakdownPerLevel;
  final Map<int, Map<int, double>>? optimalCostBreakdownPerLevel;

  // New fields for split results
  final List<EnchantResult> resultsTo10;
  final List<EnchantResult> results10ToTarget;
  final Map<int, Map<String, double>> optimalSummaryTo10;
  final Map<int, Map<String, double>> optimalSummary10ToTarget;

  OptimalCalculationResult({
    required this.resultsToTarget,
    required this.optimalExpectedCostPerLevel,
    required this.optimalExpectedStonesPerLevel,
    required this.optimalStoneUsageSummary,
    this.optimalStonesBreakdownPerLevel,
    this.optimalCostBreakdownPerLevel,
    // Add new fields to constructor
    required this.resultsTo10,
    required this.results10ToTarget,
    required this.optimalSummaryTo10,
    required this.optimalSummary10ToTarget,
  });
}

class ManualCalculationResult {
  final List<EnchantResult> manualPathResults;
  final Map<int, Map<String, double>> manualStoneUsageSummary;

  ManualCalculationResult({
    required this.manualPathResults,
    required this.manualStoneUsageSummary,
  });
}
