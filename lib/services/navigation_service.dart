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

    final avoidParts = <String>[];
    if (avoidTolls) avoidParts.add('tolls');
    if (avoidHighways) avoidParts.add('highways');

    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': 'driving',
      'alternatives': includeAlternatives ? 'true' : 'false',
      'departure_time': 'now',
      'traffic_model': 'best_guess',
      if (avoidParts.isNotEmpty) 'avoid': avoidParts.join('|'),
      'key': apiKey,
    });

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw NavigationException('Directions request failed (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['status']?.toString() ?? 'UNKNOWN';
    if (status != 'OK') {
      final error = data['error_message']?.toString();
      throw NavigationException('Directions API error: $status${error != null ? ' - $error' : ''}');
    }

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
      final duration = firstLeg['duration'] as Map<String, dynamic>?;
      final durationInTraffic = firstLeg['duration_in_traffic'] as Map<String, dynamic>?;
      final distance = firstLeg['distance'] as Map<String, dynamic>?;

      final encoded = (route['overview_polyline'] as Map<String, dynamic>?)?['points']?.toString() ?? '';
      final points = _decodePolyline(encoded);

      options.add(
        RouteOption(
          routeId: 'route_$i',
          summary: route['summary']?.toString().trim().isNotEmpty == true
              ? route['summary'].toString()
              : 'Option ${i + 1}',
          points: points,
          durationSeconds: (duration?['value'] as num?)?.toInt() ?? 0,
          durationInTrafficSeconds: (durationInTraffic?['value'] as num?)?.toInt(),
          distanceMeters: (distance?['value'] as num?)?.toInt() ?? 0,
          durationText: duration?['text']?.toString() ?? 'Unknown',
          durationInTrafficText: durationInTraffic?['text']?.toString(),
          distanceText: distance?['text']?.toString() ?? 'Unknown',
        ),
      );
    }

    options.sort((a, b) => a.effectiveDurationSeconds.compareTo(b.effectiveDurationSeconds));
    return options;
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
}
