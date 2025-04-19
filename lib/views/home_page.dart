import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:math';

import '../models/enchant_models.dart';
import '../services/enchant_service.dart';
import '../services/storage_service.dart';
import '../main.dart';

// Update constructor to accept theme colors
class HomePage extends StatefulWidget {
  const HomePage({
    super.key, 
    required this.title,
    required this.accentColor,
    required this.successColor,
    required this.errorColor,
  });

  final String title;
  final Color accentColor;
  final Color successColor;
  final Color errorColor;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Services
  final EnchantService _enchantService = EnchantService();
  final StorageService _storageService = StorageService();

  // UI State & Configuration
  int _selectedItemLevel = 60;
  final List<int> _itemLevelOptions = [55, 56, 57, 58, 59, 60];

  int _currentEnchantLevel = 0;
  final List<int> _enchantLevelOptions = List.generate(15, (index) => index);

  int _targetEnchantLevel = 15; // Target level state
  List<int> _targetLevelOptions = []; // Options for target dropdown

  final List<int> _stoneLevels = [
    ...List.generate(15, (index) => 91 + index), // 91 to 105
    110,
    115,
  ];
  final Map<int, TextEditingController> _priceControllers = {};
  Map<int, double> _stonePrices = {}; // Loaded from storage

  double _selectedSupplement = 0.0;
  final List<double> _supplementOptions = [0.0, 5.0, 10.0, 15.0];

  // Calculation Results
  List<EnchantResult> _resultsToTarget = [];
  Map<int, IndividualStoneCalcResult> _individualStoneResults = {};
  Map<int, double> _optimalExpectedCostPerLevel = {};
  Map<int, double> _optimalExpectedStonesPerLevel = {};

  // Add these two fields to store breakdowns for manual path recovery
  Map<int, Map<int, double>> _optimalStonesBreakdownPerLevel = {};
  Map<int, Map<int, double>> _optimalCostBreakdownPerLevel = {};

  // NEW: State variables for split optimal results
  List<EnchantResult> _resultsTo10 = [];
  List<EnchantResult> _results10ToTarget = [];
  Map<int, Map<String, double>> _optimalSummaryTo10 = {};
  Map<int, Map<String, double>> _optimalSummary10ToTarget = {};

  // Manual Path State
  final Map<int, int> _manualStoneSelection = {}; // enchant level -> stone level
  final Map<int, double> _manualSupplements = {}; // enchant level -> supplement percentage
  List<EnchantResult> _manualPathResults = [];
  Map<int, Map<String, double>> _manualStoneUsageSummary = {};
  bool _showManualPathSection = false;

  // Loading/State Flags
  bool _isLoading = false;
  bool _pricesLoaded = false; // Tracks if initial prices have been loaded

  // Formatters
  final NumberFormat _resultPriceFormatter = NumberFormat.decimalPattern('de_DE');

  // Add a FocusNode for each price input
  final Map<int, FocusNode> _priceFocusNodes = {};

  @override
  void initState() {
    super.initState();
    
    // Initialize controllers before loading prices
    for (int level in _stoneLevels) {
      _priceControllers[level] = TextEditingController(text: '0');
      _stonePrices[level] = 0.0; // Initialize price map
      _priceFocusNodes[level] = FocusNode(); // Add this line
    }

    // Set up controller listeners after initialization
    for (int level in _stoneLevels) {
      _priceControllers[level]!.addListener(() {
        String text = _priceControllers[level]!.text;
        String digitsOnly = text.replaceAll(RegExp(r'[^\d]'), '');
        // Update the price map directly
        _stonePrices[level] = double.tryParse(digitsOnly) ?? 0.0;
        // Update individual stats immediately when price changes
        _updateIndividualStoneStats();
      });
      _individualStoneResults[level] = IndividualStoneCalcResult(); // Initialize results map
    }
    
    // Update target options
    _updateTargetLevelOptions();
    
    // Initialize manual selections (up to +14 attempt) 
    for (int level = 10; level < 15; level++) {
      _manualStoneSelection[level] = 105; // Default
      _manualSupplements[level] = 0.0; // Default
    }
    _manualSupplements[13] = 5.0; // Example default
    _manualSupplements[14] = 10.0; // Example default
 
    // Load prices with a slight delay to ensure SharedPreferences is ready
    Future.delayed(const Duration(milliseconds: 100), () {
      _loadPricesAndInitStats();
    });
  }

  @override
  void dispose() {
    for (var controller in _priceControllers.values) {
      controller.dispose();
    }
    // Dispose all focus nodes
    for (var node in _priceFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  // Helper to update target level options based on current level
  void _updateTargetLevelOptions() {
    // Target must be at least current + 1, up to 15
    _targetLevelOptions = List.generate(15 - _currentEnchantLevel, (index) => _currentEnchantLevel + 1 + index);
    // Ensure the selected target level is still valid
    if (!_targetLevelOptions.contains(_targetEnchantLevel)) {
      _targetEnchantLevel = _targetLevelOptions.isNotEmpty ? _targetLevelOptions.last : _currentEnchantLevel + 1;
      if (_targetEnchantLevel > 15) _targetEnchantLevel = 15; // Cap at 15
    }
    // Ensure target is always > current
    if (_targetEnchantLevel <= _currentEnchantLevel && _targetLevelOptions.isNotEmpty) {
      _targetEnchantLevel = _targetLevelOptions.first;
    } else if (_targetLevelOptions.isEmpty) {
      // Handle case where current is already 14, target must be 15
      _targetEnchantLevel = 15;
      _targetLevelOptions = [15];
    }
  }

  Future<void> _loadPricesAndInitStats() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final loadedPrices = await _storageService.loadPrices(_stoneLevels, _priceControllers);
      if (!mounted) return;
      setState(() {
        _stonePrices = loadedPrices;
        _pricesLoaded = true;
        _updateIndividualStoneStats(); // Calculate initial stats after prices load
      });
    } catch (e) {
      print("Error loading prices: $e");
      if (mounted) {
        setState(() {
          _pricesLoaded = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Updates only the individual stone stats based on current selections
  void _updateIndividualStoneStats() {
    if (!mounted || !_pricesLoaded) return;
    final newIndividualResults = <int, IndividualStoneCalcResult>{};
    for (int stoneLevel in _stoneLevels) {
      // Individual stats calculation remains focused on +10 and +15 potential for the table
      newIndividualResults[stoneLevel] = _enchantService.calculateIndividualStoneStats(
        stoneLevel: stoneLevel,
        selectedItemLevel: _selectedItemLevel,
        currentEnchantLevel: _currentEnchantLevel,
        selectedSupplement: _selectedSupplement,
      );
      // Update costs within the individual results based on current prices
      final price = _stonePrices[stoneLevel] ?? 0.0;
      final currentStats = newIndividualResults[stoneLevel]!;
      final cost10 = currentStats.possibleTo10 && currentStats.stonesToPlus10 != double.infinity
          ? currentStats.stonesToPlus10 * price
          : double.infinity;
      final cost15 = currentStats.possibleTo15 && currentStats.stonesPlus10To15 != double.infinity
          ? currentStats.stonesPlus10To15 * price
          : double.infinity;
      newIndividualResults[stoneLevel] = currentStats.copyWithCosts(
          newCostToPlus10: cost10, newCostPlus10To15: cost15);
    }
    setState(() {
      _individualStoneResults = newIndividualResults;
      // Clear optimal/manual results as they need recalculation via button press
      _resultsToTarget = [];
      _manualPathResults = [];
      _manualStoneUsageSummary = {};
    });
  }

  // Triggered by the main "Calculate" button
  void _runCalculations() async {
    setState(() {
      _isLoading = true;
      // Clear previous results before calculating new ones
      _resultsToTarget = [];
      _optimalExpectedCostPerLevel.clear();
      _optimalExpectedStonesPerLevel.clear();
      _manualPathResults = [];
      _manualStoneUsageSummary = {};
      _optimalStonesBreakdownPerLevel = {};
      _optimalCostBreakdownPerLevel = {};
      // Clear split results as well
      _resultsTo10 = [];
      _results10ToTarget = [];
      _optimalSummaryTo10 = {};
      _optimalSummary10ToTarget = {};
    });

    // 1. Save current prices - with better error handling
    bool saveSuccess = await _storageService.savePrices(_stoneLevels, _stonePrices);
    if (!saveSuccess) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Warning: Failed to save prices'))
        );
      }
    }

    // 2. Recalculate individual stats with latest prices (important!)
    _updateIndividualStoneStats(); // Ensures costs in the table are up-to-date

    // 3. Run optimal calculation in a microtask
    Future.microtask(() {
      bool hasPrices = _stonePrices.values.any((price) => price > 0);

      if (hasPrices && _currentEnchantLevel < _targetEnchantLevel) {
        final optimalResult = _enchantService.calculateOptimalCombination(
          currentEnchantLevel: _currentEnchantLevel,
          targetLevel: _targetEnchantLevel,
          selectedItemLevel: _selectedItemLevel,
          selectedSupplement: _selectedSupplement,
          stoneLevels: _stoneLevels,
          stonePrices: _stonePrices,
        );

        if (mounted) {
          setState(() {
            // Assign full range results (optional, could be removed if not needed)
            _resultsToTarget = optimalResult.resultsToTarget;

            // Assign per-level data
            _optimalExpectedCostPerLevel = optimalResult.optimalExpectedCostPerLevel;
            _optimalExpectedStonesPerLevel = optimalResult.optimalExpectedStonesPerLevel;
            _optimalStonesBreakdownPerLevel = optimalResult.optimalStonesBreakdownPerLevel ?? {};
            _optimalCostBreakdownPerLevel = optimalResult.optimalCostBreakdownPerLevel ?? {};

            // Assign NEW split results
            _resultsTo10 = optimalResult.resultsTo10;
            _results10ToTarget = optimalResult.results10ToTarget;
            _optimalSummaryTo10 = optimalResult.optimalSummaryTo10;
            _optimalSummary10ToTarget = optimalResult.optimalSummary10ToTarget;
          });
        }
      } else {
        if (mounted) {
          // Handle case where no prices are entered or target <= current
          if (!hasPrices) {
            print("Calculation skipped: No prices entered.");
          } else {
            print("Calculation skipped: Target level must be greater than current level.");
            // Optionally clear results or show a message
            setState(() {
              _resultsToTarget = [];
            });
          }
        }
      }
    }).whenComplete(() {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  // Triggered by the "Calculate Manual Path" button
  void _calculateManualPath() {
    // Manual path only makes sense for targets > 10
    if (_targetEnchantLevel <= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manual path planning is only available for target levels above +10.')));
      return;
    }

    // Check if optimal calculation providing base recovery to +10 is needed and available
    if ((_optimalStonesBreakdownPerLevel.isEmpty || _optimalCostBreakdownPerLevel.isEmpty) && _currentEnchantLevel < 10) {
      // Need optimal path first to get recovery data if starting below +10
      _runCalculations();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Optimal path calculated first to determine recovery costs. Please press "Calculate Manual Path" again.')));
      return;
    }
    // Also check if the specific recovery cost for +10 exists if starting >= 10
    if (_currentEnchantLevel >= 10 && !_optimalExpectedCostPerLevel.containsKey(9)) {
      // Need optimal path to calculate base recovery cost even if starting at 10+
      _runCalculations();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Optimal path calculated first to determine base recovery cost. Please press "Calculate Manual Path" again.')));
      return;
    }

    setState(() {
      _isLoading = true; // Show loading indicator
      _manualPathResults = []; // Clear previous manual results
      _manualStoneUsageSummary = {};
    });

    Future.microtask(() {
      final manualResult = _enchantService.calculateManualPath(
        currentEnchantLevel: _currentEnchantLevel,
        targetLevel: _targetEnchantLevel,
        selectedItemLevel: _selectedItemLevel,
        stoneLevels: _stoneLevels,
        stonePrices: _stonePrices,
        manualStoneSelection: _manualStoneSelection,
        manualSupplements: _manualSupplements,
        optimalExpectedCostPerLevel: _optimalExpectedCostPerLevel,
        optimalExpectedStonesPerLevel: _optimalExpectedStonesPerLevel,
        optimalStonesBreakdownPerLevel: _optimalStonesBreakdownPerLevel,
        optimalCostBreakdownPerLevel: _optimalCostBreakdownPerLevel,
      );

      if (mounted) {
        setState(() {
          _manualPathResults = manualResult.manualPathResults;
          _manualStoneUsageSummary = manualResult.manualStoneUsageSummary;
        });
      }
    }).whenComplete(() {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  // Help dialog
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help & Information'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How to use the calculator:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('1. Set your item level and enhancement levels'),
              Text('2. Enter stone prices for available stones'),
              Text('3. Press "Calculate" to find optimal paths'),
              SizedBox(height: 16),
              Text('Understanding success rates:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('C+1: Success chance for +0 to +1'),
              Text('C+11: Success chance for +10 to +11'),
              SizedBox(height: 16),
              Text('Understanding colors:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• Green indicators: 50%+ chance (good)'),
              Text('• Orange indicators: 20-50% chance (average)'),
              Text('• Red indicators: Below 20% chance (poor)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Helper function to handle moving focus and selecting text
  void _handleFocusMoveNext(int currentLevel) {
    int currentIndex = _stoneLevels.indexOf(currentLevel);
    if (currentIndex < _stoneLevels.length - 1) {
      int nextLevel = _stoneLevels[currentIndex + 1];
      FocusNode nextNode = _priceFocusNodes[nextLevel]!;
      TextEditingController nextController = _priceControllers[nextLevel]!;

      // Request focus directly on the node
      nextNode.requestFocus();

      // After the frame, select text in the newly focused node
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Check if the node actually gained focus before trying to select
        if (nextNode.hasFocus) {
          nextController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: nextController.text.length,
          );
        }
      });
    } else {
      // If it's the last field, unfocus to dismiss keyboard
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Define local colors from theme
    final primaryColor = Theme.of(context).colorScheme.primary;
    final secondaryColor = Theme.of(context).colorScheme.secondary;
    final accentColor = widget.accentColor;
    final successColor = widget.successColor;
    final errorColor = widget.errorColor;
    final backgroundColor = Theme.of(context).colorScheme.surface;
    
    final cardHeaderBg = primaryColor.withOpacity(0.05);
    final tableHeaderBg = primaryColor.withOpacity(0.08);
    final highlightRowColor = secondaryColor.withOpacity(0.08);
    
    // Show loading screen until initial prices are loaded
    if (!_pricesLoaded) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                primaryColor.withOpacity(0.1),
                backgroundColor,
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_graph,
                  size: 80,
                  color: primaryColor,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Enchant Calculator',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Main UI scaffold with improved design
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showHelpDialog(),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              primaryColor.withOpacity(0.05),
              backgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Configuration Card
                _buildCard(
                  title: 'Configuration',
                  icon: Icons.settings,
                  color: primaryColor,
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final bool isWideScreen = constraints.maxWidth > 600;                            
                          return isWideScreen
                            ? _buildWideConfigControls()
                            : _buildNarrowConfigControls();
                        },
                      ),
                      
                      const SizedBox(height: 16),
                      // Calculate button
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _runCalculations,
                          icon: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Theme.of(context).colorScheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.calculate),
                          label: const Text('Calculate Optimal Path'),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Stone Prices Section
                _buildStonePricesSection(
                  primaryColor: primaryColor, 
                  secondaryColor: secondaryColor,
                  successColor: successColor,
                  warningColor: accentColor,
                  errorColor: errorColor,
                ),
                
                // Results Section
                if (!_isLoading && (_resultsTo10.isNotEmpty || _results10ToTarget.isNotEmpty)) 
                  _buildResultsSection(
                    primaryColor: primaryColor,
                    secondaryColor: secondaryColor,
                    accentColor: accentColor,
                    tableHeaderBg: tableHeaderBg,
                    highlightRowColor: highlightRowColor,
                  ),
                
                // Manual Path Section (If needed)
                if (_targetEnchantLevel > 10) 
                  _buildManualPathSection(
                    accentColor: accentColor,
                    cardHeaderBg: cardHeaderBg,
                  ),
                  
                // No results message
                if (!_isLoading && _resultsToTarget.isEmpty && _currentEnchantLevel < _targetEnchantLevel)
                  _buildNoResultsMessage(
                    warningColor: accentColor,
                    primaryColor: primaryColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  // Updated card builder with consistent styling
  Widget _buildCard({
    required String title, 
    required IconData icon,
    required Widget child,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header with gradient
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              border: Border(bottom: BorderSide(color: color.withOpacity(0.1), width: 1)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          // Card content
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: child,
          ),
        ],
      ),
    );
  }
  
  // Updated stone prices section with improved grid layout
  Widget _buildStonePricesSection({
    required Color primaryColor,
    required Color secondaryColor,
    required Color successColor,
    required Color warningColor,
    required Color errorColor,
  }) {
    return _buildCard(
      title: 'Stone Prices',
      icon: Icons.diamond_outlined,
      color: secondaryColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stone prices grid with improved layout
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                childAspectRatio: MediaQuery.of(context).size.width > 600 ? 3.5 : 2.8, // Adjusted for better proportions
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _stoneLevels.length,
              itemBuilder: (context, index) {
                final level = _stoneLevels[index];
                return _buildStonePriceInput(
                  level, 
                  primaryColor: primaryColor,
                  secondaryColor: secondaryColor,
                  successColor: successColor,
                  warningColor: warningColor,
                  errorColor: errorColor,
                );
              },
            ),
          ),
          
          const Divider(height: 32),
          
          // Enhanced footer with better styling
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: primaryColor.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: primaryColor),
                    const SizedBox(width: 6),
                    Text(
                      'Enter stone prices above',
                      style: TextStyle(
                        fontSize: 12, 
                        fontWeight: FontWeight.w500,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
  
  // Completely redesigned stone price input with improved space utilization
  Widget _buildStonePriceInput(
    int level, {
    required Color primaryColor,
    required Color secondaryColor,
    required Color successColor,
    required Color warningColor,
    required Color errorColor,
  }) {
    final result = _individualStoneResults[level] ?? IndividualStoneCalcResult();
    final chance0 = (result.successRatePlus0 * 100).toStringAsFixed(1);
    final chance10 = (result.successRatePlus10 * 100).toStringAsFixed(1);
    
    // Group stone levels for color coding and improved aesthetics
    final bool isHighLevel = level >= 101; 
    final bool isSpecialLevel = level == 110 || level == 115;
    
    // Use a more cohesive color scheme
    Color levelBgColor;
    Color levelTextColor;
    Color levelBorderColor;
    
    if (isSpecialLevel) {
      // Premium stones get special treatment
      levelBgColor = warningColor.withOpacity(0.08);
      levelTextColor = warningColor;
      levelBorderColor = warningColor.withOpacity(0.2);
    } else if (isHighLevel) {
      // High tier stones (101-105)
      levelBgColor = secondaryColor.withOpacity(0.08);
      levelTextColor = secondaryColor; 
      levelBorderColor = secondaryColor.withOpacity(0.15);
    } else {
      // Base stones (91-100)
      levelBgColor = primaryColor.withOpacity(0.05);
      levelTextColor = primaryColor;
      levelBorderColor = primaryColor.withOpacity(0.12);
    }
    
    // Enhanced container with better depth and modern styling
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 5,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: levelBorderColor),
      ),
      child: Column(
        children: [
          // Top section with level indicator and price field
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Stone level indicator with new design
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: levelBgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: levelBorderColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Optional icon for visual distinction
                        if (isSpecialLevel) ...[
                          Icon(Icons.star, size: 12, color: levelTextColor),
                          const SizedBox(width: 4),
                        ] else if (isHighLevel) ...[
                          Icon(Icons.arrow_upward, size: 12, color: levelTextColor),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          '$level',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: levelTextColor,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Price input with enhanced styling
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade50,
                      ),
                      child: Focus(
                        focusNode: _priceFocusNodes[level], // Assign focus node here
                        onFocusChange: (hasFocus) {
                          final controller = _priceControllers[level]!;
                          // No need for setState here, controller changes trigger updates
                          if (hasFocus) {
                            if (controller.text == '0') {
                              controller.clear();
                            }
                          } else {
                            if (controller.text.trim().isEmpty) {
                              controller.text = '0';
                            }
                          }
                        },
                        // *** Add onKeyEvent handler ***
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
                            // Handle Tab press manually
                            _handleFocusMoveNext(level);
                            // Prevent default Tab behavior
                            return KeyEventResult.handled;
                          }
                          // Allow other keys (like Enter, characters) to be processed normally
                          return KeyEventResult.ignored;
                        },
                        child: TextFormField(
                          controller: _priceControllers[level],
                          // FocusNode is now assigned to the parent Focus widget
                          // focusNode: _priceFocusNodes[level],
                          decoration: InputDecoration(
                            // ... existing decoration ...
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: levelTextColor, width: 1.5),
                            ),
                            prefix: IgnorePointer(
                              ignoring: true,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 4, right: 4),
                                child: Icon(
                                  Icons.attach_money,
                                  size: 16,
                                  color: isSpecialLevel
                                      ? warningColor
                                      : isHighLevel
                                          ? secondaryColor
                                          : primaryColor,
                                ),
                              ),
                            ),
                            prefixIconConstraints: null,
                          ),
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            ThousandsFormatter(),
                          ],
                          enabled: !_isLoading,
                          // Set textInputAction to done for the last field, next for others
                          textInputAction: _stoneLevels.indexOf(level) < _stoneLevels.length - 1
                              ? TextInputAction.next
                              : TextInputAction.done,
                          // *** Remove onEditingComplete ***
                          // onEditingComplete: () { ... } // Logic moved to onKeyEvent
                          // Handle Enter key press explicitly if needed (onKeyEvent handles Tab)
                          onFieldSubmitted: (value) {
                             // This is typically triggered by Enter key
                             _handleFocusMoveNext(level);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Bottom section with clean divider and success indicators
          Container(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey.shade100, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildEnhancedChanceIndicator(
                  '+1', 
                  chance0,
                  successColor: successColor, 
                  warningColor: warningColor, 
                  errorColor: errorColor,
                ),
                const SizedBox(width: 8),
                Container(
                  height: 16,
                  width: 1,
                  color: Colors.grey.shade200,
                ),
                const SizedBox(width: 8),
                _buildEnhancedChanceIndicator(
                  '+11', 
                  chance10,
                  successColor: successColor, 
                  warningColor: warningColor, 
                  errorColor: errorColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Enhanced chance indicator with better visual design
  Widget _buildEnhancedChanceIndicator(
    String label, 
    String percentage, {
    required Color successColor,
    required Color warningColor,
    required Color errorColor,
  }) {
    final double chance = double.tryParse(percentage) ?? 0;
    Color textColor;
    Color bgColor;
    IconData? icon;
    
    if (chance >= 50) {
      textColor = successColor;
      bgColor = successColor.withOpacity(0.08);
      icon = Icons.check_circle_outline;
    } else if (chance >= 20) {
      textColor = warningColor;
      bgColor = warningColor.withOpacity(0.08);
      icon = Icons.info_outline;
    } else if (chance > 0) {
      textColor = errorColor;
      bgColor = errorColor.withOpacity(0.08);
      icon = Icons.warning_amber_outlined;
    } else {
      textColor = Colors.grey.shade500;
      bgColor = Colors.transparent;
      icon = null;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12), // More rounded for a modern look
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: textColor),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 10, color: textColor, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 3),
          Text(
            '$percentage%',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
  
  // Updated results section with tabs
  Widget _buildResultsSection({
    required Color primaryColor,
    required Color secondaryColor,
    required Color accentColor,
    required Color tableHeaderBg,
    required Color highlightRowColor,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefaultTabController(
            length: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Card header with tabs below
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.08),
                    border: Border(bottom: BorderSide(color: primaryColor.withOpacity(0.1), width: 1)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.insights, size: 20, color: primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Optimal Results',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                
                TabBar(
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.arrow_circle_up_outlined, 
                            size: 16, 
                            color: _resultsTo10.isEmpty ? Colors.grey : primaryColor
                          ),
                          const SizedBox(width: 6),
                          const Text('Base (+0 to +10)'),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.star_outline, 
                            size: 16, 
                            color: _results10ToTarget.isEmpty ? Colors.grey : secondaryColor
                          ),
                          const SizedBox(width: 6),
                          const Text('Advanced (+10 to +15)'),
                        ],
                      ),
                    ),
                  ],
                  indicatorSize: TabBarIndicatorSize.tab,
                ),
                
                SizedBox(
                  height: 400,
                  child: TabBarView(
                    children: [
                      // First Tab: Base results to +10
                      _buildBaseResultsTab(
                        primaryColor: primaryColor,
                        tableHeaderBg: tableHeaderBg,
                        highlightRowColor: highlightRowColor,
                      ),
                      
                      // Second Tab: Advanced results from +10 to +15
                      _buildAdvancedResultsTab(
                        secondaryColor: secondaryColor,
                        tableHeaderBg: tableHeaderBg.withBlue(tableHeaderBg.blue + 10), // Slightly different hue
                        highlightRowColor: highlightRowColor,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Updated base results tab
  Widget _buildBaseResultsTab({
    required Color primaryColor,
    required Color tableHeaderBg,
    required Color highlightRowColor,
  }) {
    if (_resultsTo10.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text('No results for +0 to +10 enhancement path'),
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Optimal Path +$_currentEnchantLevel to +10',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildModernResultsTable(
              _resultsTo10,
              headerColor: tableHeaderBg,
              highlightColor: highlightRowColor,
              accentColor: primaryColor,
            ),
          ),
          
          const SizedBox(height: 24),
          
          if (_optimalSummaryTo10.isNotEmpty) ...[
            Text(
              'Stone Usage Summary',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildModernSummaryTable(
                summary: _optimalSummaryTo10,
                headerColor: tableHeaderBg,
                totalRowColor: primaryColor.withOpacity(0.1),
                accentColor: primaryColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  // Updated advanced results tab
  Widget _buildAdvancedResultsTab({
    required Color secondaryColor,
    required Color tableHeaderBg,
    required Color highlightRowColor,
  }) {
    if (_results10ToTarget.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text('No results for +10 to +15 enhancement path'),
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Optimal Path +10 to +$_targetEnchantLevel',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: secondaryColor,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildModernResultsTable(
              _results10ToTarget,
              headerColor: tableHeaderBg,
              highlightColor: highlightRowColor,
              accentColor: secondaryColor,
            ),
          ),
          
          const SizedBox(height: 24),
          
          if (_optimalSummary10ToTarget.isNotEmpty) ...[
            Text(
              'Stone Usage Summary',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: secondaryColor,
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildModernSummaryTable(
                summary: _optimalSummary10ToTarget,
                headerColor: tableHeaderBg,
                totalRowColor: secondaryColor.withOpacity(0.1),
                accentColor: secondaryColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  // No results message with improved design
  Widget _buildNoResultsMessage({
    required Color warningColor,
    required Color primaryColor,
  }) {
    return Center(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 48, color: warningColor),
              const SizedBox(height: 16),
              const Text(
                'No Optimal Path Found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Could not determine an optimal path to the target level.\nCheck if success rates are possible or if prices are entered for necessary stones.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Scroll to stone prices section
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                ),
                child: const Text('Update Stone Prices'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Updated results table with consistent styling
  Widget _buildModernResultsTable(
    List<EnchantResult> results, {
    required Color headerColor,
    required Color highlightColor,
    required Color accentColor,
  }) {
    if (results.isEmpty) return const SizedBox.shrink();
    
    // Modern table implementation
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: DataTable(
          columnSpacing: 16,
          headingRowHeight: 52,
          dataRowHeight: 56,
          headingRowColor: WidgetStateProperty.all(headerColor),
          decoration: const BoxDecoration(color: Colors.white),
          horizontalMargin: 16,
          columns: const [
            DataColumn(label: Text('Level', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Stone', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Success %', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Cost', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Total Cost', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          ],
          rows: results.map((result) {
            final level = result.enchantLevel;
            final nextLevel = level + 1;
            bool isHighlight = nextLevel == 10 || nextLevel == 15;
            
            return DataRow(
              color: isHighlight ? WidgetStateProperty.all(highlightColor) : null,
              cells: [
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isHighlight ? accentColor.withOpacity(0.1) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isHighlight ? accentColor.withOpacity(0.3) : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      '+$nextLevel',
                      style: TextStyle(
                        fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
                        color: isHighlight ? accentColor : Colors.black87,
                      ),
                    ),
                  ),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('${result.bestStoneLevel}'),
                  )
                ),
                DataCell(Text(
                  '${(result.successRate * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                )),
                DataCell(Text(
                  _resultPriceFormatter.format(result.expectedCostForLevel),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                )),
                DataCell(Text(
                  _resultPriceFormatter.format(result.cumulativeExpectedCost),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
  
  // Updated summary table with ceiling for stone counts
  Widget _buildModernSummaryTable({
    required Map<int, Map<String, double>> summary,
    required Color headerColor,
    required Color totalRowColor,
    required Color accentColor,
  }) {
    final usedStones = summary.entries
        .where((entry) => (entry.value['count'] ?? 0.0) > 0.01)
        .toList()
        ..sort((a, b) => a.key.compareTo(b.key));

    if (usedStones.isEmpty) return const SizedBox.shrink();

    double totalStones = usedStones.fold(0.0, (sum, entry) => sum + (entry.value['count'] ?? 0.0));
    double totalCost = usedStones.fold(0.0, (sum, entry) => sum + (entry.value['cost'] ?? 0.0));

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: DataTable(
          columnSpacing: 16,
          headingRowHeight: 52,
          dataRowHeight: 56,
          headingRowColor: WidgetStateProperty.all(headerColor),
          decoration: const BoxDecoration(color: Colors.white),
          horizontalMargin: 16,
          columns: const [
            DataColumn(label: Text('Stone', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
            DataColumn(label: Text('Cost', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          ],
          rows: [
            ...usedStones.map((entry) {
              final stoneLevel = entry.key;
              final count = entry.value['count'] ?? 0.0;
              final cost = entry.value['cost'] ?? 0.0;
              final bool isHighLevel = stoneLevel >= 101;
              
              return DataRow(
                color: isHighLevel ? WidgetStateProperty.all(Colors.grey.shade50) : null,
                cells: [
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isHighLevel 
                          ? accentColor.withOpacity(0.1) 
                          : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isHighLevel 
                            ? accentColor.withOpacity(0.3) 
                            : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        'Level $stoneLevel',
                        style: TextStyle(
                          fontWeight: isHighLevel ? FontWeight.w500 : FontWeight.normal,
                          color: isHighLevel ? accentColor : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  // Changed to display the ceiling value for stone count
                  DataCell(Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(count.ceil().toString()),
                  )),
                  DataCell(Text(_resultPriceFormatter.format(cost))),
                ],
              );
            }),
            DataRow(
              color: WidgetStateProperty.all(totalRowColor),
              cells: [
                DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, color: accentColor))),
                // Changed to display ceiling for total stones as well
                DataCell(Text(totalStones.ceil().toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text(_resultPriceFormatter.format(totalCost), style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  // *** ADDED: Implementation for config controls ***
  Widget _buildWideConfigControls() {
    return Row(
      children: [
        Expanded(child: _buildItemLevelDropdown()),
        const SizedBox(width: 12),
        Expanded(child: _buildCurrentEnchantDropdown()),
        const SizedBox(width: 12),
        Expanded(child: _buildTargetEnchantDropdown()),
        const SizedBox(width: 12),
        Expanded(child: _buildSupplementDropdown()),
      ],
    );
  }

  // *** ADDED: Implementation for config controls ***
  Widget _buildNarrowConfigControls() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildItemLevelDropdown()),
            const SizedBox(width: 12),
            Expanded(child: _buildCurrentEnchantDropdown()),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildTargetEnchantDropdown()),
            const SizedBox(width: 12),
            Expanded(child: _buildSupplementDropdown()),
          ],
        ),
        ],
    );
  }

  // *** ADDED: Implementation for dropdowns ***
  Widget _buildItemLevelDropdown() {
    return _buildDropdownField(
      label: 'Item Level',
      value: _selectedItemLevel,
      items: _itemLevelOptions.map((value) =>
        DropdownMenuItem<int>(value: value, child: Text('Level $value'))
      ).toList(),
      onChanged: _isLoading ? null : (int? newValue) {
        if (newValue != null && newValue != _selectedItemLevel) {
          setState(() {
            _selectedItemLevel = newValue;
            _updateIndividualStoneStats(); // Recalculate stats on change
          });
        }
      },
    );
  }

  // *** ADDED: Implementation for dropdowns ***
  Widget _buildCurrentEnchantDropdown() {
    return _buildDropdownField(
      label: 'Current Level',
      value: _currentEnchantLevel,
      items: _enchantLevelOptions.map((value) =>
        DropdownMenuItem<int>(value: value, child: Text('+$value'))
      ).toList(),
      onChanged: _isLoading ? null : (int? newValue) {
        if (newValue != null && newValue != _currentEnchantLevel) {
          setState(() {
            _currentEnchantLevel = newValue;
            _updateTargetLevelOptions(); // Update target options based on new current level
            _updateIndividualStoneStats(); // Recalculate stats on change
          });
        }
      },
    );
  }

  // *** ADDED: Implementation for dropdowns ***
  Widget _buildTargetEnchantDropdown() {
    return _buildDropdownField(
      label: 'Target Level',
      value: _targetEnchantLevel,
      items: _targetLevelOptions.map((value) =>
        DropdownMenuItem<int>(value: value, child: Text('+$value'))
      ).toList(),
      // Disable if only one option or loading
      onChanged: (_isLoading || _targetLevelOptions.length <= 1)
        ? null
        : (int? newValue) {
            if (newValue != null && newValue != _targetEnchantLevel) {
              setState(() {
                _targetEnchantLevel = newValue;
                // Clear results as they are now invalid for the new target
                _resultsToTarget = [];
                _manualPathResults = [];
                _manualStoneUsageSummary = {};
                _resultsTo10 = [];
                _results10ToTarget = [];
                _optimalSummaryTo10 = {};
                _optimalSummary10ToTarget = {};
              });
            }
          },
    );
  }

  // *** ADDED: Implementation for dropdowns ***
  Widget _buildSupplementDropdown() {
    return _buildDropdownField(
      label: 'Supplement',
      value: _selectedSupplement,
      items: _supplementOptions.map((value) =>
        DropdownMenuItem<double>(value: value, child: Text('${value.toInt()}%'))
      ).toList(),
      onChanged: _isLoading ? null : (double? newValue) {
        if (newValue != null && newValue != _selectedSupplement) {
          setState(() {
            _selectedSupplement = newValue;
            _updateIndividualStoneStats(); // Recalculate stats on change
          });
        }
      },
    );
  }

  // *** ADDED: Generic dropdown field builder ***
  Widget _buildDropdownField<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              )
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              menuMaxHeight: 300,
              borderRadius: BorderRadius.circular(8),
              icon: const Icon(Icons.keyboard_arrow_down),
              onChanged: onChanged,
              items: items,
              style: Theme.of(context).textTheme.bodyMedium,
              dropdownColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // Updated manual path section with better color scheme
  Widget _buildManualPathSection({
    required Color accentColor,
    required Color cardHeaderBg,
  }) {
    // Define a rich purple color that complements our app's blue theme
    const Color manualSectionColor = Color(0xFF8E44AD); // Purple color for manual path
    
    if (!_showManualPathSection) {
      return Center(
        child: TextButton.icon(
          onPressed: () {
            setState(() {
              _showManualPathSection = true;
            });
          },
          icon: Icon(Icons.add_circle_outline, color: manualSectionColor),
          label: Text(
            'Show Manual +10 to +$_targetEnchantLevel Planning',
            style: TextStyle(color: manualSectionColor),
          ),
        ),
      );
    }
    
    final manualLevelWidgets = <Widget>[]; // Define list here
    
    // Generate the manual stone selection controls
    for (int index = 0; index < (_targetEnchantLevel > 10 ? min(_targetEnchantLevel - 10, 5) : 0); index++) {
      final level = 10 + index;
      manualLevelWidgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              // Level indicator with consistent styling
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: manualSectionColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '+${level + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: manualSectionColor,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              
              // Stone selection dropdown
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Stone', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _manualStoneSelection[level] ?? 105,
                          isExpanded: true,
                          items: _stoneLevels
                              .where((s) => s >= 101 && (_stonePrices[s] ?? 0) > 0)
                              .map((s) => DropdownMenuItem<int>(
                                    value: s,
                                    child: Text('Level $s'),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _manualStoneSelection[level] = value;
                                // Clear results when selection changes
                                _manualPathResults = [];
                                _manualStoneUsageSummary = {};
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              
              // Supplement selection dropdown
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Supplement', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<double>(
                          value: _manualSupplements[level] ?? 0.0,
                          isExpanded: true,
                          items: _supplementOptions
                              .map((s) => DropdownMenuItem<double>(
                                    value: s,
                                    child: Text('${s.toInt()}%'),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _manualSupplements[level] = value;
                                // Clear results when selection changes
                                _manualPathResults = [];
                                _manualStoneUsageSummary = {};
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Updated manual section header with purple theme
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: manualSectionColor.withOpacity(0.1),
              border: Border(bottom: BorderSide(color: manualSectionColor.withOpacity(0.2), width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.edit, size: 20, color: manualSectionColor),
                    const SizedBox(width: 8),
                    Text(
                      'Manual Enhancement Planning',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: manualSectionColor,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.expand_less, color: manualSectionColor),
                  onPressed: () {
                    setState(() {
                      _showManualPathSection = false;
                    });
                  },
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configure each step from +10 to +$_targetEnchantLevel:',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: manualSectionColor,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Add the manually created widgets list here
                ...manualLevelWidgets,
                
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _calculateManualPath,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.play_arrow),
                    label: const Text('Calculate Manual Path'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: manualSectionColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                
                // Display manual results if available
                if (_manualPathResults.isNotEmpty) ...[
                  const Divider(height: 32),
                  Text(
                    'Manual Path Results',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: manualSectionColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildModernResultsTable(
                      _manualPathResults,
                      headerColor: manualSectionColor.withOpacity(0.1),
                      highlightColor: manualSectionColor.withOpacity(0.05),
                      accentColor: manualSectionColor,
                    ),
                  ),
                  
                  if (_manualStoneUsageSummary.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Manual Path Stone Usage',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: manualSectionColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildModernSummaryTable(
                        summary: _manualStoneUsageSummary,
                        headerColor: manualSectionColor.withOpacity(0.1),
                        totalRowColor: manualSectionColor.withOpacity(0.15),
                        accentColor: manualSectionColor,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
