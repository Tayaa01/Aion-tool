import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'views/home_page.dart'; // Add this import for HomePage
import 'services/storage_service.dart';

// --- Custom Thousands Formatter (Keep here or move to utils) ---
class ThousandsFormatter extends TextInputFormatter {
  final NumberFormat _formatter;

  // Use a locale like 'de_DE' or 'es_ES' which use '.' as a grouping separator
  ThousandsFormatter() : _formatter = NumberFormat.decimalPattern('de_DE');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    // Allow deletion
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Get digits only
    final String digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    try {
      // Format the number
      final int number = int.parse(digitsOnly);
      final String formattedText = _formatter.format(number);

      // --- Calculate new cursor position ---
      int originalCursorPos = newValue.selection.baseOffset;
      int digitsBeforeCursor = 0;
      for (int i = 0; i < originalCursorPos; i++) {
        if (RegExp(r'\d').hasMatch(newValue.text[i])) {
          digitsBeforeCursor++;
        }
      }

      int newCursorPos = 0;
      int digitsCounted = 0;
      while (newCursorPos < formattedText.length && digitsCounted < digitsBeforeCursor) {
        if (RegExp(r'\d').hasMatch(formattedText[newCursorPos])) {
          digitsCounted++;
        }
        newCursorPos++;
      }
       while (newCursorPos < formattedText.length && !RegExp(r'\d').hasMatch(formattedText[newCursorPos])) {
         newCursorPos++;
       }
      newCursorPos = newCursorPos.clamp(0, formattedText.length);
      // --- End cursor calculation ---

      return TextEditingValue(
        text: formattedText,
        selection: TextSelection.collapsed(offset: newCursorPos),
      );
    } catch (e) {
      // In case of error (e.g., number too large for int), return the previous value
      // Consider logging the error: print("Error in ThousandsFormatter: $e");
      return oldValue;
    }
  }
}

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set orientation preferences
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]); 
  
  // Web-specific debug output
  if (kIsWeb) {
    print('Running in web environment. Initializing storage...');
  }
  
  // Initialize SharedPreferences only once at app start
  await SharedPreferences.getInstance();
  print('SharedPreferences instance obtained.'); // Debug log
  
  // Initialize storage service
  final storageService = StorageService();
  
  // For debugging: dump storage contents *after* ensuring instance is ready
  await storageService.debugStorageContents();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Enhanced color palette with more vibrant, balanced colors
    const Color primaryColor = Color(0xFF3550B4);      // Rich blue
    const Color secondaryColor = Color(0xFF5C7CFF);    // Brighter blue
    const Color accentColor = Color(0xFFFFAB40);       // Warm amber
    const Color purpleAccent = Color(0xFF8E44AD);      // Rich purple for manual section
    const Color backgroundColor = Color(0xFFF8F9FC);   // Light blue/gray background
    const Color surfaceColor = Colors.white;
    const Color errorColor = Color(0xFFE53935);        // Red
    const Color successColor = Color(0xFF43A047);      // Green
    const Color warningColor = Color(0xFFF9A825);      // Amber
    
    return MaterialApp(
      title: 'Enchant Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme(
          brightness: Brightness.light,
          primary: primaryColor,
          onPrimary: Colors.white,
          secondary: secondaryColor,
          onSecondary: Colors.white,
          tertiary: purpleAccent,            // Added tertiary for manual path
          onTertiary: Colors.white,
          error: errorColor,
          onError: Colors.white,
          background: backgroundColor,
          onBackground: Colors.black87,
          surface: surfaceColor,
          onSurface: Colors.black87,
        ),
        
        // Enhanced typography with slightly better spacing
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontSize: 22.0,
            fontWeight: FontWeight.w600,
            color: primaryColor,
            letterSpacing: 0.2,
          ),
          titleMedium: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2D3748),
            letterSpacing: 0.1,
          ),
          titleSmall: TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.w500,
            color: Color(0xFF2D3748),
            letterSpacing: 0.1,
          ),
          bodyLarge: TextStyle(
            fontSize: 16.0,
            color: Color(0xFF2D3748),
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            fontSize: 14.0,
            color: Color(0xFF2D3748),
            height: 1.4,
          ),
        ),
        
        // Enhanced app bar with subtle shadow
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2, // Subtle elevation for depth
          shadowColor: Color(0x40000000),
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 0.2,
          ),
        ),
        
        // Cards with refined styling
        cardTheme: CardTheme(
          color: surfaceColor,
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.0), // Slightly more rounded
          ),
          clipBehavior: Clip.antiAlias,
        ),
        
        // Buttons with refined styling
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            elevation: 1,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.0), // Slightly more rounded
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
            minimumSize: const Size(120, 48), // Ensure minimum touch target size
          ),
        ),
        
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        
        // Form fields
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.0),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8.0)),
            borderSide: BorderSide(color: primaryColor),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        
        // Progress indicators
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: primaryColor,
        ),
        
        // Tabs
        tabBarTheme: const TabBarTheme(
          labelColor: primaryColor,
          unselectedLabelColor: Color(0xFF9E9E9E),
          indicatorColor: primaryColor,
          indicatorSize: TabBarIndicatorSize.tab,
        ),
        
        // Dividers
        dividerTheme: DividerThemeData(
          color: Colors.grey.shade200,
          thickness: 1,
          space: 32,
        ),
        
        // Scaffold background
        scaffoldBackgroundColor: backgroundColor,
      ),
      home: const HomePage(
        title: 'Enchant Calculator',
        accentColor: accentColor, 
        successColor: successColor,
        errorColor: errorColor,
      ),
    );
  }
}
