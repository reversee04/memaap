import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'config/app_config.dart';
import 'providers/emergency_provider.dart';
import 'providers/auth_provider.dart';
import 'router.dart';

void main() async {
  // Initialize AppConfig before runApp()
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.initialize();

  // Initialize Google Maps Android Renderer to prevent dynamite core renderer crashes
  try {
    final GoogleMapsFlutterPlatform mapsImplementation = GoogleMapsFlutterPlatform.instance;
    if (mapsImplementation is GoogleMapsFlutterAndroid) {
      await mapsImplementation.initializeWithRenderer(AndroidMapRenderer.latest);
    }
  } catch (e) {
    debugPrint('Failed to initialize Google Maps Android renderer: $e');
  }
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EmergencyProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Malawi Medical SOS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0033CC),
          primary: const Color(0xFF0033CC),
          secondary: const Color(0xFFE53935),
          background: const Color(0xFFF5F7FA),
        ),
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      routerConfig: goRouter,
    );
  }
}
