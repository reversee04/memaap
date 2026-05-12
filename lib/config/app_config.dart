import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration class that holds all global constants and environment settings
/// for the Mobile Emergency Medical Assistance App.
/// 
/// This class manages API endpoints, authentication keys, timeout settings,
/// and environment flags. It must be initialized before runApp() is called.
class AppConfig {
  // Private constructor to prevent instantiation
  AppConfig._();

  /// Base URL for all API endpoints
  static String get baseUrl => dotenv.env['BASE_API_URL'] ?? 'https://api.memaap.com';
  
  /// Google Maps API key for mapping services
  static String get googleMapsKey => dotenv.env['GOOGLE_MAPS_KEY'] ?? '';
  
  /// SMS gateway URL for emergency notifications
  static String get smsGatewayUrl => dotenv.env['SMS_GATEWAY_URL'] ?? '';
  
  /// Default timeout duration for HTTP requests in seconds
  static int get requestTimeoutSeconds => 
      int.tryParse(dotenv.env['REQUEST_TIMEOUT_SECONDS'] ?? '') ?? 15;
  
  /// Flag indicating if the app is running in production mode
  static bool get isProduction => 
      dotenv.env['IS_PRODUCTION']?.toLowerCase() == 'true';


  /// Factory constructor that loads environment variables from .env file
  /// 
  /// Returns an instance of AppConfig after loading environment variables.
  /// Throws [Exception] if the .env file cannot be loaded.
  factory AppConfig() {
    throw UnimplementedError(
      'AppConfig should not be instantiated. Use AppConfig.initialize() instead.'
    );
  }

  /// Initializes the AppConfig by loading environment variables from .env file
  /// 
  /// This method must be called before runApp() in main.dart.
  /// It loads the .env file and makes all environment variables available
  /// through the static getters.
  /// 
  /// Throws [Exception] if the .env file cannot be loaded or required
  /// environment variables are missing.
  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: '.env');
      
      // Validate required environment variables in production
      if (isProduction) {
        _validateRequiredVars();
      }
    } catch (e) {
      throw Exception('Failed to initialize AppConfig: $e');
    }
  }

  /// Validates that all required environment variables are present
  /// 
  /// This is called automatically in production mode to ensure
  /// critical configuration values are available.
  /// 
  /// Throws [Exception] if any required variable is missing.
  static void _validateRequiredVars() {
    final requiredVars = [
      'BASE_API_URL',
      'GOOGLE_MAPS_KEY',
      'SMS_GATEWAY_URL',
    ];
    
    final missingVars = requiredVars
        .where((varName) => dotenv.env[varName]?.isEmpty ?? true)
        .toList();
    
    if (missingVars.isNotEmpty) {
      throw Exception(
        'Missing required environment variables in production: ${missingVars.join(', ')}'
      );
    }
  }

  /// Gets an environment variable by name with optional default value
  /// 
  /// [key] - The environment variable name
  /// [defaultValue] - Optional default value if the key is not found
  /// 
  /// Returns the environment variable value or the default value
  static String? getEnv(String key, [String? defaultValue]) {
    return dotenv.env[key] ?? defaultValue;
  }

  /// Checks if the app is running in development mode
  static bool get isDevelopment => !isProduction;

  /// Gets the current environment name
  static String get environment => isProduction ? 'production' : 'development';
}
