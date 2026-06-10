import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

class NavigationException implements Exception {
  final String message;

  NavigationException(this.message);

  @override
  String toString() => 'NavigationException: $message';
}

class RouteOption {
  final String routeId;
  final String summary;
  final List<LatLng> points;
  final int durationSeconds;
  final int? durationInTrafficSeconds;
  final int distanceMeters;
  final String durationText;
  final String? durationInTrafficText;
  final String distanceText;

  const RouteOption({
    required this.routeId,
    required this.summary,
    required this.points,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.durationText,
    required this.distanceText,
    this.durationInTrafficSeconds,
    this.durationInTrafficText,
  });

  int get effectiveDurationSeconds => durationInTrafficSeconds ?? durationSeconds;

  String get trafficDeltaText {
    if (durationInTrafficSeconds == null) return 'Traffic: N/A';
    final delta = durationInTrafficSeconds! - durationSeconds;
    if (delta <= 0) return 'Traffic: clear';
    final mins = (delta / 60).round();
    return 'Traffic +${mins}m';
  }
}

class NavigationService {
  static const String routesApiSetupHint =
      'Enable Routes API for this Google Cloud project and allow this API key to use it. '
      'A Places-only key is not enough for route calculation.';

  static const Duration _routesDepartureLeadTime = Duration(minutes: 1);

  static Future<List<RouteOption>> getRouteOptions({
    required LatLng origin,
    required LatLng destination,
    bool includeAlternatives = true,
    bool avoidTolls = false,
    bool avoidHighways = false,
  }) async {
    final apiKey = AppConfig.googleMapsKey;
    if (apiKey.isEmpty) {
      throw NavigationException('Google Maps API key not configured');
    }

    final uri = Uri.https(
      'routes.googleapis.com',
      '/directions/v2:computeRoutes',
    );

    final payload = <String, dynamic>{
      'origin': {
        'location': {
          'latLng': {
            'latitude': origin.latitude,
            'longitude': origin.longitude,
          },
        },
      },
      'destination': {
        'location': {
          'latLng': {
            'latitude': destination.latitude,
            'longitude': destination.longitude,
          },
        },
      },
      'travelMode': 'DRIVE',
      'routingPreference': 'TRAFFIC_AWARE_OPTIMAL',
      'computeAlternativeRoutes': includeAlternatives,
      'routeModifiers': {
        'avoidTolls': avoidTolls,
        'avoidHighways': avoidHighways,
      },
      'languageCode': 'en-US',
      'units': 'METRIC',
      'departureTime': DateTime.now()
          .toUtc()
          .add(_routesDepartureLeadTime)
          .toIso8601String(),
    };

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask':
            'routes.duration,routes.distanceMeters,routes.description,'
            'routes.polyline.encodedPolyline,routes.legs.duration,'
            'routes.legs.staticDuration,routes.legs.distanceMeters',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      String message = 'Routes request failed (${response.statusCode})';
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final error = data['error'] as Map<String, dynamic>?;
        final apiMessage = error?['message']?.toString();
        if (apiMessage != null && apiMessage.isNotEmpty) {
          message = 'Routes API error: $apiMessage';

          final normalized = apiMessage.toLowerCase();
          if (normalized.contains('not enabled') ||
              normalized.contains('api has not been used') ||
              normalized.contains('service disabled') ||
              normalized.contains('api_key_service_blocked') ||
              normalized.contains('permission denied')) {
            message = 'Routes API is not enabled for this key/project. $routesApiSetupHint';
          }
        }
      } catch (_) {
        // Keep generic message when response body is not JSON.
      }
      throw NavigationException(message);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = (data['routes'] as List<dynamic>?) ?? const [];
    if (routes.isEmpty) {
      throw NavigationException('No routes found');
    }

    final options = <RouteOption>[];
    for (var i = 0; i < routes.length; i++) {
      final route = routes[i] as Map<String, dynamic>;
      final legs = (route['legs'] as List<dynamic>?) ?? const [];
      if (legs.isEmpty) continue;

      final firstLeg = legs.first as Map<String, dynamic>;
      final duration = _parseDurationToSeconds(route['duration']?.toString()) ??
        _parseDurationToSeconds(firstLeg['duration']?.toString()) ??
        0;
      final staticDuration =
        _parseDurationToSeconds(firstLeg['staticDuration']?.toString());
      final distanceMeters =
        (route['distanceMeters'] as num?)?.toInt() ??
        (firstLeg['distanceMeters'] as num?)?.toInt() ??
        0;
      final encoded = (route['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
          ?.toString() ??
        '';
      final points = _decodePolyline(encoded);

      options.add(
        RouteOption(
          routeId: 'route_$i',
        summary: route['description']?.toString().trim().isNotEmpty == true
          ? route['description'].toString()
              : 'Option ${i + 1}',
          points: points,
        durationSeconds: staticDuration ?? duration,
        durationInTrafficSeconds: staticDuration == null ? null : duration,
        distanceMeters: distanceMeters,
        durationText: _secondsToText(staticDuration ?? duration),
        durationInTrafficText:
          staticDuration == null ? null : _secondsToText(duration),
        distanceText: _metersToText(distanceMeters),
        ),
      );
    }

    options.sort((a, b) => a.effectiveDurationSeconds.compareTo(b.effectiveDurationSeconds));
    return options;
  }

  static int? _parseDurationToSeconds(String? value) {
    if (value == null || value.isEmpty) return null;
    final cleaned = value.endsWith('s') ? value.substring(0, value.length - 1) : value;
    return int.tryParse(cleaned);
  }

  static String _secondsToText(int seconds) {
    if (seconds <= 0) return 'Unknown';
    final mins = (seconds / 60).round();
    if (mins < 60) return '${mins} min';
    final hours = mins ~/ 60;
    final remaining = mins % 60;
    if (remaining == 0) return '${hours}h';
    return '${hours}h ${remaining}m';
  }

  static String _metersToText(int meters) {
    if (meters <= 0) return 'Unknown';
    if (meters < 1000) return '${meters} m';
    final km = meters / 1000;
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km';
  }

  static Future<void> launchTurnByTurnNavigation({
    required LatLng destination,
    String? label,
  }) async {
    final destinationParam = '${destination.latitude},${destination.longitude}';

    final googleNav = Uri.parse('google.navigation:q=$destinationParam&mode=d');
    if (await canLaunchUrl(googleNav)) {
      await launchUrl(googleNav);
      return;
    }

    final webGoogleMaps = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destinationParam&travelmode=driving',
    );

    if (await canLaunchUrl(webGoogleMaps)) {
      await launchUrl(webGoogleMaps, mode: LaunchMode.externalApplication);
      return;
    }

    throw NavigationException(
      'Unable to open navigation for ${label ?? destinationParam}',
    );
  }

  static List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      final dLat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dLat;

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);

      final dLng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dLng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  static String friendlyEta(RouteOption option) {
    return option.durationInTrafficText ?? option.durationText;
  }

  static String compactDistanceKm(RouteOption option) {
    final km = option.distanceMeters / 1000;
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km';
  }

  static void logRouteSelection(RouteOption option) {
    if (kDebugMode) {
      debugPrint(
        '[NavigationService] Selected ${option.summary} (${option.durationText}, ${option.distanceText})',
      );
    }
  }

  static bool isRoutesConfigurationError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('routes api is not enabled') ||
        text.contains('places-only key') ||
        text.contains('not enabled for this key/project');
  }
}
