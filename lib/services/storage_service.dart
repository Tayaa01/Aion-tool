import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
// Removed: import 'dart:html' as html;
import 'package:intl/intl.dart';

class StorageService {
  final NumberFormat _priceInputFormatter = NumberFormat.decimalPattern('de_DE');

  // Key for storing the entire price dataset using SharedPreferences
  static const String _pricesKey = 'enchant_stone_prices_data_v2'; // Use a distinct key

  // Load prices using only SharedPreferences
  Future<Map<int, double>> loadPrices(List<int> stoneLevels, Map<int, TextEditingController> priceControllers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loadedPrices = <int, double>{};

      // Try to load the consolidated data
      final String? storedPricesJson = prefs.getString(_pricesKey);
      if (storedPricesJson != null) {
        print("Loading prices from SharedPreferences key: $_pricesKey"); // Debug log
        try {
          final Map<String, dynamic> storedData = jsonDecode(storedPricesJson);
          for (int level in stoneLevels) {
            final String levelKey = level.toString();
            if (storedData.containsKey(levelKey)) {
              // Ensure correct parsing, handle potential type issues
              final dynamic priceValue = storedData[levelKey];
              final double price = (priceValue is String)
                  ? (double.tryParse(priceValue) ?? 0.0)
                  : (priceValue as num?)?.toDouble() ?? 0.0;

              loadedPrices[level] = price;
              if (priceControllers.containsKey(level)) {
                priceControllers[level]!.text = price > 0 ? _priceInputFormatter.format(price) : '0';
              }
            } else {
              // Key not found in stored data
              if (priceControllers.containsKey(level)) {
                priceControllers[level]!.text = '0';
              }
              loadedPrices[level] = 0.0;
            }
          }
          print("Loaded prices: $loadedPrices"); // Debug log
          return loadedPrices;
        } catch (e) {
          print('Error parsing stored prices JSON from $_pricesKey: $e');
          // If parsing fails, clear the invalid key and fall through
          await prefs.remove(_pricesKey);
        }
      } else {
         print("No data found for SharedPreferences key: $_pricesKey"); // Debug log
      }

      // If no data found or parsing failed, initialize with zeros
      print("Initializing prices with zeros."); // Debug log
      for (int level in stoneLevels) {
        if (priceControllers.containsKey(level)) {
          priceControllers[level]!.text = '0';
        }
        loadedPrices[level] = 0.0;
      }
      return loadedPrices;

    } catch (e) {
      print('Error loading prices from SharedPreferences: $e');
      // Return empty prices if there's a major error
      return Map.fromIterables(stoneLevels, List.filled(stoneLevels.length, 0.0));
    }
  }

  // Save prices using only SharedPreferences
  Future<bool> savePrices(List<int> stoneLevels, Map<int, double> stonePrices) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Prepare data as a map of String keys to double values
      final Map<String, double> pricesData = {};
      for (int level in stoneLevels) {
        pricesData[level.toString()] = stonePrices[level] ?? 0.0;
      }

      // Store the consolidated data as a JSON string
      final String pricesJson = jsonEncode(pricesData);
      print("Saving to SharedPreferences key $_pricesKey: $pricesJson"); // Debug log
      bool success = await prefs.setString(_pricesKey, pricesJson);
      if (!success) {
         print("Failed to save to SharedPreferences key: $_pricesKey"); // Debug log
      } else {
         print("Successfully saved to SharedPreferences key: $_pricesKey"); // Debug log
         // Optional: Force SharedPreferences to commit changes immediately on web
         if (kIsWeb) {
           await prefs.reload(); // May help ensure data is written
         }
      }
      return success;
    } catch (e) {
      print('Error saving prices to SharedPreferences: $e');
      return false;
    }
  }

  // For debugging: dump the current state of SharedPreferences
  Future<void> debugStorageContents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final Map<String, dynamic> sharedPrefsData = {};

      print("--- Debugging SharedPreferences Contents ---");
      if (keys.isEmpty) {
        print("SharedPreferences is empty.");
      } else {
        for (String key in keys) {
          sharedPrefsData[key] = prefs.get(key);
          print("Key: $key, Value: ${sharedPrefsData[key]}"); // Print each key-value pair
        }
        // Optionally print the whole map as JSON
        // print('SharedPreferences contents (JSON): ${jsonEncode(sharedPrefsData)}');
      }
       print("--- End Debugging SharedPreferences ---");

    } catch (e) {
      print('Error debugging SharedPreferences: $e');
    }
  }

  // Helper method (remains the same)
  int ceilingStoneCount(double count) {
    return count.ceil();
  }
}
