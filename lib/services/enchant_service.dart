import 'dart:math';
import '../models/enchant_models.dart';

class EnchantService {

  // --- Core Calculation Logic ---

  double calcRate(int stone, int itemLvl, int enchantLvl, double supplement) {
    double baseRate;
    if (enchantLvl >= 10) {
      baseRate = min(max(0.5025 - (itemLvl + 57 - stone) * 0.0075, 0.0), 0.5);
    } else {
      baseRate = min(max(0.81 - (itemLvl + 44 - stone) * 0.015, 0.0), 0.8);
    }
    return min(baseRate + (supplement / 100.0), 1.0);
  }

  Map<String, double> _calculateStonesFromZero(int stoneLevel, int targetLevel, int selectedItemLevel, double selectedSupplement) {
    Map<int, double> expectedStones = {};
    double cumulativeStones = 0;
    bool possible = true;

    for (int e = 0; e < targetLevel; e++) {
      double rate = calcRate(stoneLevel, selectedItemLevel, e, selectedSupplement);
      if (rate <= 0) {
        possible = false;
        break;
      }

      double stonesToRecover = 0;
      if (e >= 10) {
        bool recoveryPossible = true;
        for (int recoveryLevel = 10; recoveryLevel < e; recoveryLevel++) {
          double stonesForRecLevel = expectedStones[recoveryLevel] ?? double.infinity;
          if (stonesForRecLevel == double.infinity) {
            recoveryPossible = false;
            break;
          }
          stonesToRecover += stonesForRecLevel;
        }
        if (!recoveryPossible) {
          possible = false;
          break;
        }
      } else if (e > 0) {
        stonesToRecover = expectedStones[e - 1] ?? double.infinity;
        if (stonesToRecover == double.infinity) {
          possible = false;
          break;
        }
      }

      double nES = _calculateExpectedStones(rate, stonesToRecover); // Use helper
      if (nES.isInfinite || nES.isNaN) {
        possible = false;
        break;
      }
      expectedStones[e] = nES;
      cumulativeStones += nES;
    }

    return {'cumulative': possible ? cumulativeStones : double.infinity, 'possible': possible ? 1.0 : 0.0};
  }

  IndividualStoneCalcResult calculateIndividualStoneStats({
    required int stoneLevel,
    required int selectedItemLevel,
    required int currentEnchantLevel,
    required double selectedSupplement,
  }) {
    double initialRate = calcRate(stoneLevel, selectedItemLevel, 0, selectedSupplement);
    double ratePlus10 = calcRate(stoneLevel, selectedItemLevel, 10, selectedSupplement);

    Map<String, double> statsToCurrent = _calculateStonesFromZero(stoneLevel, currentEnchantLevel, selectedItemLevel, selectedSupplement);
    Map<String, double> statsTo10 = _calculateStonesFromZero(stoneLevel, 10, selectedItemLevel, selectedSupplement);
    Map<String, double> statsTo15 = _calculateStonesFromZero(stoneLevel, 15, selectedItemLevel, selectedSupplement);

    bool possibleFromCurrentTo10 = (statsToCurrent['possible'] == 1.0) && (statsTo10['possible'] == 1.0);
    double stonesFromCurrentTo10 = possibleFromCurrentTo10
        ? (statsTo10['cumulative']! - statsToCurrent['cumulative']!)
        : double.infinity;

    int startLevelFor15 = max(currentEnchantLevel, 10);
    Map<String, double> statsToStart15 = _calculateStonesFromZero(stoneLevel, startLevelFor15, selectedItemLevel, selectedSupplement);

    bool possibleFromStart15To15 = (statsToStart15['possible'] == 1.0) && (statsTo15['possible'] == 1.0);
    double stonesFromStart15To15 = possibleFromStart15To15
        ? (statsTo15['cumulative']! - statsToStart15['cumulative']!)
        : double.infinity;

    if (currentEnchantLevel >= 10) stonesFromCurrentTo10 = 0;
    if (currentEnchantLevel >= 15) stonesFromStart15To15 = 0;

    return IndividualStoneCalcResult(
      successRatePlus0: initialRate,
      successRatePlus10: ratePlus10,
      stonesToPlus10: max(0, stonesFromCurrentTo10),
      stonesPlus10To15: max(0, stonesFromStart15To15),
      possibleTo10: currentEnchantLevel < 10 ? possibleFromCurrentTo10 : true,
      possibleTo15: currentEnchantLevel < 15 ? possibleFromStart15To15 : true,
    );
  }

  double _calculateExpectedStones(double successRate, double failureRecoveryStones) {
    if (successRate <= 0) return double.infinity;
    return (1 / successRate) + ((1 - successRate) / successRate) * failureRecoveryStones;
  }

  // --- Optimal Path Calculation ---

  OptimalCalculationResult calculateOptimalCombination({
    required int currentEnchantLevel,
    required int targetLevel,
    required int selectedItemLevel,
    required double selectedSupplement,
    required List<int> stoneLevels,
    required Map<int, double> stonePrices,
  }) {
    final List<EnchantResult> resultsToTarget = [];
    final List<EnchantResult> resultsTo10 = [];
    final List<EnchantResult> results10ToTarget = [];

    final Map<int, double> optimalTotalStonesPerLevel = {};
    final Map<int, double> optimalTotalCostPerLevel = {};
    final Map<int, Map<int, double>> optimalStonesBreakdownPerLevel = {};
    final Map<int, Map<int, double>> optimalCostBreakdownPerLevel = {};

    final Map<int, Map<String, double>> finalOptimalSummary = {};
    final Map<int, Map<String, double>> optimalSummaryTo10 = {};
    final Map<int, Map<String, double>> optimalSummary10ToTarget = {};

    final Map<int, double> optimalExpectedCostPerLevel = {};
    final Map<int, double> optimalExpectedStonesPerLevel = {};

    double cumulativeCost = 0.0;
    double cumulativeStones = 0.0;
    
    // We'll use these to ensure proper tracking of the 10-to-target calculations
    // without affecting the overall calculation
    double cumulativeCostFrom10 = 0.0;
    double cumulativeStonesFrom10 = 0.0;

    if (currentEnchantLevel >= targetLevel) {
      return OptimalCalculationResult(
          resultsToTarget: [],
          optimalExpectedCostPerLevel: {},
          optimalExpectedStonesPerLevel: {},
          optimalStoneUsageSummary: {},
          resultsTo10: [],
          results10ToTarget: [],
          optimalSummaryTo10: {},
          optimalSummary10ToTarget: {},
      );
    }

    final List<int> availableStones = stoneLevels
        .where((s) => (stonePrices[s] ?? 0) > 0)
        .toList()..sort();

    if (availableStones.isEmpty) {
      return OptimalCalculationResult(
          resultsToTarget: [],
          optimalExpectedCostPerLevel: {},
          optimalExpectedStonesPerLevel: {},
          optimalStoneUsageSummary: {},
          resultsTo10: [],
          results10ToTarget: [],
          optimalSummaryTo10: {},
          optimalSummary10ToTarget: {},
      );
    }

    Map<int, double> prevLevelStonesBreakdown = {};
    Map<int, double> prevLevelCostBreakdown = {};
    Map<int, double> recoveryStonesBreakdownForPlus10 = {};
    Map<int, double> recoveryCostBreakdownForPlus10 = {};
    double totalRecoveryCostForPlus10 = 0;

    if (targetLevel > 10) {
        Map<String, dynamic> recovery9Result = _calculateRecoveryPathForPlus10(
            selectedItemLevel: selectedItemLevel,
            selectedSupplement: selectedSupplement,
            stoneLevels: stoneLevels,
            stonePrices: stonePrices
        );
        if (recovery9Result['bestStone'] != -1) {
            int recStone9 = recovery9Result['bestStone'];
            recoveryStonesBreakdownForPlus10 = {recStone9: recovery9Result['stones']};
            recoveryCostBreakdownForPlus10 = {recStone9: recovery9Result['cost']};
            totalRecoveryCostForPlus10 = recovery9Result['cost'];
            optimalExpectedStonesPerLevel.putIfAbsent(9, () => recovery9Result['stones']);
            optimalExpectedCostPerLevel.putIfAbsent(9, () => recovery9Result['cost']);
            optimalStonesBreakdownPerLevel.putIfAbsent(9, () => recoveryStonesBreakdownForPlus10);
            optimalCostBreakdownPerLevel.putIfAbsent(9, () => recoveryCostBreakdownForPlus10);
        } else {
            totalRecoveryCostForPlus10 = double.infinity;
        }
    }

    // First process all levels from currentEnchantLevel to targetLevel
    for (int level = currentEnchantLevel; level < targetLevel; level++) {
      int bestStone = -1;
      double minTotalCost = double.infinity;
      double bestStoneSuccessRate = 0.0;

      Map<int, double> currentRecoveryStonesBreakdown = {};
      Map<int, double> currentRecoveryCostBreakdown = {};
      double currentTotalRecoveryCost = 0;

      if (level < 9) {
          currentRecoveryStonesBreakdown = prevLevelStonesBreakdown;
          currentRecoveryCostBreakdown = prevLevelCostBreakdown;
          currentTotalRecoveryCost = prevLevelCostBreakdown.values.fold(0.0, (a, b) => a + b);
      } else if (level == 9) {
          currentRecoveryStonesBreakdown = prevLevelStonesBreakdown;
          currentRecoveryCostBreakdown = prevLevelCostBreakdown;
          currentTotalRecoveryCost = prevLevelCostBreakdown.values.fold(0.0, (a, b) => a + b);
          // Save recovery path for plus 10
          recoveryStonesBreakdownForPlus10 = Map.from(prevLevelStonesBreakdown);
          recoveryCostBreakdownForPlus10 = Map.from(prevLevelCostBreakdown);
          totalRecoveryCostForPlus10 = currentTotalRecoveryCost;
      } else {
          if (totalRecoveryCostForPlus10 == double.infinity) {
              optimalTotalStonesPerLevel[level] = double.infinity; optimalTotalCostPerLevel[level] = double.infinity;
              optimalExpectedStonesPerLevel[level] = double.infinity; optimalExpectedCostPerLevel[level] = double.infinity;
              break;
          }
          // For level 10 and above, start with recoveryStonesBreakdownForPlus10
          currentRecoveryStonesBreakdown = Map.from(recoveryStonesBreakdownForPlus10);
          currentRecoveryCostBreakdown = Map.from(recoveryCostBreakdownForPlus10);

          bool recoveryPathFrom10Possible = true;
          for (int recLvl = 10; recLvl < level; recLvl++) {
              Map<int, double>? stonesMap = optimalStonesBreakdownPerLevel[recLvl];
              Map<int, double>? costMap = optimalCostBreakdownPerLevel[recLvl];
              if (stonesMap == null || costMap == null || optimalTotalCostPerLevel[recLvl] == double.infinity) {
                  recoveryPathFrom10Possible = false;
                  break;
              }
              stonesMap.forEach((stone, count) => currentRecoveryStonesBreakdown[stone] = (currentRecoveryStonesBreakdown[stone] ?? 0) + count);
              costMap.forEach((stone, cost) => currentRecoveryCostBreakdown[stone] = (currentRecoveryCostBreakdown[stone] ?? 0) + cost);
          }

          if (!recoveryPathFrom10Possible) {
              optimalTotalStonesPerLevel[level] = double.infinity; optimalTotalCostPerLevel[level] = double.infinity;
              optimalExpectedStonesPerLevel[level] = double.infinity; optimalExpectedCostPerLevel[level] = double.infinity;
              break;
          }
          currentTotalRecoveryCost = currentRecoveryCostBreakdown.values.fold(0.0, (a, b) => a + b);
      }

      List<int> stonesToConsider = (level >= 10 && stoneLevels.any((s) => s >= 101 && (stonePrices[s] ?? 0) > 0))
          ? availableStones.where((s) => s >= 101).toList()
          : availableStones;
      if (stonesToConsider.isEmpty) stonesToConsider = availableStones;

      for (int stoneLevel in stonesToConsider) {
        double successRate = calcRate(stoneLevel, selectedItemLevel, level, selectedSupplement);
        if (successRate <= 0) continue;
        double stonePrice = stonePrices[stoneLevel] ?? 0;
        if (stonePrice <= 0) continue;
        double expectedCost = (stonePrice / successRate) + ((1 - successRate) / successRate) * currentTotalRecoveryCost;

        if (expectedCost < minTotalCost) {
          minTotalCost = expectedCost;
          bestStone = stoneLevel;
          bestStoneSuccessRate = successRate;
        }
      }

      if (bestStone != -1 && minTotalCost != double.infinity) {
        double stonePrice = stonePrices[bestStone]!;
        double directAttempts = 1 / bestStoneSuccessRate;
        double numRecoveries = (1 - bestStoneSuccessRate) / bestStoneSuccessRate;

        Map<int, double> levelStonesBreakdown = {};
        Map<int, double> levelCostBreakdown = {};

        levelStonesBreakdown[bestStone] = (levelStonesBreakdown[bestStone] ?? 0) + directAttempts;
        levelCostBreakdown[bestStone] = (levelCostBreakdown[bestStone] ?? 0) + (directAttempts * stonePrice);
        finalOptimalSummary.putIfAbsent(bestStone, () => {'count': 0.0, 'cost': 0.0});
        finalOptimalSummary[bestStone]!['count'] = (finalOptimalSummary[bestStone]!['count'] ?? 0) + directAttempts;
        finalOptimalSummary[bestStone]!['cost'] = (finalOptimalSummary[bestStone]!['cost'] ?? 0) + (directAttempts * stonePrice);

        if (level < 10) {
          optimalSummaryTo10.putIfAbsent(bestStone, () => {'count': 0.0, 'cost': 0.0});
          optimalSummaryTo10[bestStone]!['count'] = (optimalSummaryTo10[bestStone]!['count'] ?? 0) + directAttempts;
          optimalSummaryTo10[bestStone]!['cost'] = (optimalSummaryTo10[bestStone]!['cost'] ?? 0) + (directAttempts * stonePrice);
        } else {
          optimalSummary10ToTarget.putIfAbsent(bestStone, () => {'count': 0.0, 'cost': 0.0});
          optimalSummary10ToTarget[bestStone]!['count'] = (optimalSummary10ToTarget[bestStone]!['count'] ?? 0) + directAttempts;
          optimalSummary10ToTarget[bestStone]!['cost'] = (optimalSummary10ToTarget[bestStone]!['cost'] ?? 0) + (directAttempts * stonePrice);
        }

        if (numRecoveries > 0 && currentTotalRecoveryCost > 0) {
          currentRecoveryStonesBreakdown.forEach((recStone, recCount) {
            double stonesToAdd = numRecoveries * recCount;
            levelStonesBreakdown[recStone] = (levelStonesBreakdown[recStone] ?? 0) + stonesToAdd;
            finalOptimalSummary.putIfAbsent(recStone, () => {'count': 0.0, 'cost': 0.0});
            finalOptimalSummary[recStone]!['count'] = (finalOptimalSummary[recStone]!['count'] ?? 0) + stonesToAdd;
            if (level < 10) {
              optimalSummaryTo10.putIfAbsent(recStone, () => {'count': 0.0, 'cost': 0.0});
              optimalSummaryTo10[recStone]!['count'] = (optimalSummaryTo10[recStone]!['count'] ?? 0) + stonesToAdd;
            } else {
              optimalSummary10ToTarget.putIfAbsent(recStone, () => {'count': 0.0, 'cost': 0.0});
              optimalSummary10ToTarget[recStone]!['count'] = (optimalSummary10ToTarget[recStone]!['count'] ?? 0) + stonesToAdd;
            }
          });
          currentRecoveryCostBreakdown.forEach((recStone, recCost) {
            double costToAdd = numRecoveries * recCost;
            levelCostBreakdown[recStone] = (levelCostBreakdown[recStone] ?? 0) + costToAdd;
            finalOptimalSummary.putIfAbsent(recStone, () => {'count': 0.0, 'cost': 0.0});
            finalOptimalSummary[recStone]!['cost'] = (finalOptimalSummary[recStone]!['cost'] ?? 0) + costToAdd;
            if (level < 10) {
              optimalSummaryTo10.putIfAbsent(recStone, () => {'count': 0.0, 'cost': 0.0});
              optimalSummaryTo10[recStone]!['cost'] = (optimalSummaryTo10[recStone]!['cost'] ?? 0) + costToAdd;
            } else {
              optimalSummary10ToTarget.putIfAbsent(recStone, () => {'count': 0.0, 'cost': 0.0});
              optimalSummary10ToTarget[recStone]!['cost'] = (optimalSummary10ToTarget[recStone]!['cost'] ?? 0) + costToAdd;
            }
          });
        }

        optimalStonesBreakdownPerLevel[level] = levelStonesBreakdown;
        optimalCostBreakdownPerLevel[level] = levelCostBreakdown;
        prevLevelStonesBreakdown = levelStonesBreakdown;
        prevLevelCostBreakdown = levelCostBreakdown;

        double totalExpectedStonesForLevel = levelStonesBreakdown.values.fold(0.0, (a, b) => a + b);
        double totalExpectedCostForLevel = levelCostBreakdown.values.fold(0.0, (a, b) => a + b);
        optimalTotalStonesPerLevel[level] = totalExpectedStonesForLevel;
        optimalTotalCostPerLevel[level] = totalExpectedCostForLevel;
        optimalExpectedStonesPerLevel[level] = totalExpectedStonesForLevel;
        optimalExpectedCostPerLevel[level] = totalExpectedCostForLevel;

        cumulativeStones += totalExpectedStonesForLevel;
        cumulativeCost += totalExpectedCostForLevel;

        // Record the full path result
        final result = EnchantResult(
          enchantLevel: level, 
          bestStoneLevel: bestStone, 
          expectedCostForLevel: totalExpectedCostForLevel,
          cumulativeExpectedCost: cumulativeCost,
          // Always ceiling stone counts
          expectedStonesNeeded: totalExpectedStonesForLevel.ceil(),
          cumulativeStones: cumulativeStones.ceil(),
          successRate: bestStoneSuccessRate, 
          supplement: selectedSupplement,
        );
        resultsToTarget.add(result);

        // Split the results for +0 to +10 and +10 to +15
        if (level < 10) {
          resultsTo10.add(result);
        } else {
          // For levels 10+, we need to track a separate cumulative count
          // Starting from the first level after 9
          if (level == 10) {
            // Initialize the +10 to Target tracking with the correct total cost
            cumulativeCostFrom10 = totalExpectedCostForLevel;
            cumulativeStonesFrom10 = totalExpectedStonesForLevel;
          } else {
            cumulativeCostFrom10 += totalExpectedCostForLevel;
            cumulativeStonesFrom10 += totalExpectedStonesForLevel;
          }

          // Create a separate result entry for the +10 to target view
          results10ToTarget.add(EnchantResult(
            enchantLevel: level, 
            bestStoneLevel: bestStone, 
            expectedCostForLevel: totalExpectedCostForLevel,
            cumulativeExpectedCost: cumulativeCostFrom10,
            // Always ceiling stone counts
            expectedStonesNeeded: totalExpectedStonesForLevel.ceil(),
            cumulativeStones: cumulativeStonesFrom10.ceil(),
            successRate: bestStoneSuccessRate, 
            supplement: selectedSupplement,
          ));
        }
      } else {
        optimalTotalStonesPerLevel[level] = double.infinity;
        optimalTotalCostPerLevel[level] = double.infinity;
        optimalExpectedStonesPerLevel[level] = double.infinity;
        optimalExpectedCostPerLevel[level] = double.infinity;
        break;
      }
    }

    return OptimalCalculationResult(
      resultsToTarget: resultsToTarget,
      optimalExpectedCostPerLevel: optimalExpectedCostPerLevel,
      optimalExpectedStonesPerLevel: optimalExpectedStonesPerLevel,
      optimalStoneUsageSummary: finalOptimalSummary,
      optimalStonesBreakdownPerLevel: optimalStonesBreakdownPerLevel,
      optimalCostBreakdownPerLevel: optimalCostBreakdownPerLevel,
      resultsTo10: resultsTo10,
      results10ToTarget: results10ToTarget,
      optimalSummaryTo10: optimalSummaryTo10,
      optimalSummary10ToTarget: optimalSummary10ToTarget,
    );
  }

  Map<String, dynamic> _calculateRecoveryPathForPlus10({
    required int selectedItemLevel,
    required double selectedSupplement,
    required List<int> stoneLevels,
    required Map<int, double> stonePrices,
  }) {
    final List<int> availableStones = stoneLevels
        .where((s) => (stonePrices[s] ?? 0) > 0)
        .toList()..sort();

    if (availableStones.isEmpty) {
      return {'bestStone': -1, 'cost': double.infinity, 'stones': double.infinity};
    }

    int bestStone = -1;
    double minTotalCost = double.infinity;
    double bestStoneExpectedStones = 0.0;

    for (int stoneLevel in availableStones) {
      double successRate = calcRate(stoneLevel, selectedItemLevel, 9, selectedSupplement);
      if (successRate <= 0) continue;
      double stonePrice = stonePrices[stoneLevel] ?? 0;
      if (stonePrice <= 0) continue;

      double expectedStones = _calculateExpectedStones(successRate, 0);
      double expectedCost = stonePrice / successRate;

      if (expectedCost < minTotalCost) {
        minTotalCost = expectedCost;
        bestStone = stoneLevel;
        bestStoneExpectedStones = expectedStones;
      }
    }

    if (bestStone != -1) {
      return {'bestStone': bestStone, 'cost': minTotalCost, 'stones': bestStoneExpectedStones};
    } else {
      return {'bestStone': -1, 'cost': double.infinity, 'stones': double.infinity};
    }
  }

  ManualCalculationResult calculateManualPath({
    required int currentEnchantLevel,
    required int targetLevel,
    required int selectedItemLevel,
    required List<int> stoneLevels,
    required Map<int, double> stonePrices,
    required Map<int, int> manualStoneSelection,
    required Map<int, double> manualSupplements,
    required Map<int, double> optimalExpectedCostPerLevel,
    required Map<int, double> optimalExpectedStonesPerLevel,
    required Map<int, Map<int, double>> optimalStonesBreakdownPerLevel,
    required Map<int, Map<int, double>> optimalCostBreakdownPerLevel,
  }) {
    final List<EnchantResult> manualResults = [];
    final Map<int, Map<String, double>> manualStoneUsageSummary = {};
    final Map<int, double> manualTotalStonesPerLevel = {};
    final Map<int, double> manualTotalCostPerLevel = {};
    final Map<int, Map<int, double>> manualStonesBreakdownPerLevel = {};
    final Map<int, Map<int, double>> manualCostBreakdownPerLevel = {};

    double cumulativeManualCost = 0.0;
    double cumulativeManualStones = 0.0;
    int startLevel = max(currentEnchantLevel, 10);

    if (startLevel >= targetLevel || targetLevel <= 10) {
        return ManualCalculationResult(
            manualPathResults: manualResults,
            manualStoneUsageSummary: manualStoneUsageSummary
        );
    }

    for (int level = startLevel; level < targetLevel; level++) {
      int selectedStone = manualStoneSelection[level] ?? -1;
      double selectedSupplement = manualSupplements[level] ?? 0.0;

      if (selectedStone == -1 || (stonePrices[selectedStone] ?? 0) <= 0) {
        manualTotalStonesPerLevel[level] = double.infinity;
        manualTotalCostPerLevel[level] = double.infinity;
        break;
      }

      double successRate = calcRate(selectedStone, selectedItemLevel, level, selectedSupplement);
      if (successRate <= 0) {
        manualTotalStonesPerLevel[level] = double.infinity;
        manualTotalCostPerLevel[level] = double.infinity;
        break;
      }

      Map<int, double> currentRecoveryStonesBreakdown = {};
      Map<int, double> currentRecoveryCostBreakdown = {};
      double currentTotalRecoveryCost = 0;

      if (level > 10) {
        bool recoveryPathFrom10Possible = true;
        for (int recLvl = 10; recLvl < level; recLvl++) {
          Map<int, double>? stonesMap = manualStonesBreakdownPerLevel[recLvl];
          Map<int, double>? costMap = manualCostBreakdownPerLevel[recLvl];
          if (stonesMap == null || costMap == null || manualTotalCostPerLevel[recLvl] == double.infinity) {
            recoveryPathFrom10Possible = false;
            break;
          }
          stonesMap.forEach((stone, count) => currentRecoveryStonesBreakdown[stone] = (currentRecoveryStonesBreakdown[stone] ?? 0) + count);
          costMap.forEach((stone, cost) => currentRecoveryCostBreakdown[stone] = (currentRecoveryCostBreakdown[stone] ?? 0) + cost);
        }

        if (!recoveryPathFrom10Possible) {
          manualTotalStonesPerLevel[level] = double.infinity;
          manualTotalCostPerLevel[level] = double.infinity;
          break;
        }
        currentTotalRecoveryCost = currentRecoveryCostBreakdown.values.fold(0.0, (a, b) => a + b);
      }

      double stonePrice = stonePrices[selectedStone]!;
      double directAttempts = 1 / successRate;
      double numRecoveries = (1 - successRate) / successRate;

      Map<int, double> levelStonesBreakdown = {};
      Map<int, double> levelCostBreakdown = {};

      levelStonesBreakdown[selectedStone] = (levelStonesBreakdown[selectedStone] ?? 0) + directAttempts;
      levelCostBreakdown[selectedStone] = (levelCostBreakdown[selectedStone] ?? 0) + (directAttempts * stonePrice);
      manualStoneUsageSummary.putIfAbsent(selectedStone, () => {'count': 0.0, 'cost': 0.0});
      manualStoneUsageSummary[selectedStone]!['count'] = (manualStoneUsageSummary[selectedStone]!['count'] ?? 0) + directAttempts;
      manualStoneUsageSummary[selectedStone]!['cost'] = (manualStoneUsageSummary[selectedStone]!['cost'] ?? 0) + (directAttempts * stonePrice);

      if (numRecoveries > 0 && currentTotalRecoveryCost > 0) {
        currentRecoveryStonesBreakdown.forEach((recStone, recCount) {
          double stonesToAdd = numRecoveries * recCount;
          levelStonesBreakdown[recStone] = (levelStonesBreakdown[recStone] ?? 0) + stonesToAdd;
          manualStoneUsageSummary.putIfAbsent(recStone, () => {'count': 0.0, 'cost': 0.0});
          manualStoneUsageSummary[recStone]!['count'] = (manualStoneUsageSummary[recStone]!['count'] ?? 0) + stonesToAdd;
        });
        currentRecoveryCostBreakdown.forEach((recStone, recCost) {
          double costToAdd = numRecoveries * recCost;
          levelCostBreakdown[recStone] = (levelCostBreakdown[recStone] ?? 0) + costToAdd;
          manualStoneUsageSummary.putIfAbsent(recStone, () => {'count': 0.0, 'cost': 0.0});
          manualStoneUsageSummary[recStone]!['cost'] = (manualStoneUsageSummary[recStone]!['cost'] ?? 0) + costToAdd;
        });
      }

      manualStonesBreakdownPerLevel[level] = levelStonesBreakdown;
      manualCostBreakdownPerLevel[level] = levelCostBreakdown;

      double totalExpectedStonesForLevel = levelStonesBreakdown.values.fold(0.0, (a, b) => a + b);
      double totalExpectedCostForLevel = levelCostBreakdown.values.fold(0.0, (a, b) => a + b);

      manualTotalStonesPerLevel[level] = totalExpectedStonesForLevel;
      manualTotalCostPerLevel[level] = totalExpectedCostForLevel;

      cumulativeManualStones += totalExpectedStonesForLevel;
      cumulativeManualCost += totalExpectedCostForLevel;

      manualResults.add(EnchantResult(
        enchantLevel: level,
        bestStoneLevel: selectedStone,
        expectedCostForLevel: totalExpectedCostForLevel,
        cumulativeExpectedCost: cumulativeManualCost,
        // Always ceiling stone counts
        expectedStonesNeeded: totalExpectedStonesForLevel.ceil(),
        cumulativeStones: cumulativeManualStones.ceil(),
        successRate: successRate,
        supplement: selectedSupplement,
      ));
    }

    return ManualCalculationResult(
        manualPathResults: manualResults,
        manualStoneUsageSummary: manualStoneUsageSummary
    );
  }
}
