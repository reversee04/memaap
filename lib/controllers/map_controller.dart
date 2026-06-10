import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';
import '../models/hospital_model.dart';
import '../services/navigation_service.dart';

/// Custom exceptions for map operations
class MapException implements Exception {
  final String message;
  
  MapException(this.message);
  
  @override
  String toString() => 'MapException: $message';
}

/// Controller class that wraps the Google Maps Flutter widget.
/// 
/// Controls markers, route drawing, camera animation, and live ambulance
/// position updates on the map for the Mobile Emergency Medical Assistance App.
class MapController {
  GoogleMapController? _googleMapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final Map<String, MarkerId> _markerIds = {};
  final Map<String, BitmapDescriptor> _markerIcons = {};
  
  MapType _currentMapType = MapType.normal;
  
  /// Gets the current GoogleMapController
  GoogleMapController? get controller => _googleMapController;
  
  /// Gets the current set of markers
  Set<Marker> get markers => Set.unmodifiable(_markers);
  
  /// Gets the current set of polylines (routes)
  Set<Polyline> get polylines => Set.unmodifiable(_polylines);
  
  /// Gets the current map type
  MapType get currentMapType => _currentMapType;

  /// Initializes the map controller
  /// 
  /// [controller] - The GoogleMapController instance
  static Future<void> initMap(GoogleMapController controller) async {
    // This would be called from the widget that creates the GoogleMap
    // In a real implementation, you'd pass this controller to the MapController instance
  }

  /// Initializes the MapController with a GoogleMapController
  /// 
  /// [controller] - The GoogleMapController instance
  Future<void> initialize(GoogleMapController controller) async {
    _googleMapController = controller;
    await _loadMarkerIcons();
  }

  /// Loads custom marker icons for different types
  Future<void> _loadMarkerIcons() async {
    try {
      // Load patient marker
      _markerIcons['patient'] = await _getMarkerIcon('assets/markers/patient.png', 120);
      
      // Load hospital marker
      _markerIcons['hospital'] = await _getMarkerIcon('assets/markers/hospital.png', 120);
      
      // Load ambulance marker
      _markerIcons['ambulance'] = await _getMarkerIcon('assets/markers/ambulance.png', 120);
      
      // Load default marker
      _markerIcons['default'] = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    } catch (e) {
      // Fallback to default markers if custom icons fail to load
      _markerIcons['patient'] = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      _markerIcons['hospital'] = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      _markerIcons['ambulance'] = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      _markerIcons['default'] = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
    }
  }

  /// Gets a marker icon from assets or creates a default one
  Future<BitmapDescriptor> _getMarkerIcon(String assetPath, double size) async {
    try {
      // Try to load from assets first
      final ByteData byteData = await rootBundle.load(assetPath);
      final Uint8List bytes = byteData.buffer.asUint8List();
      return BitmapDescriptor.fromBytes(bytes, size: Size(size, size));
    } catch (e) {
      // Fallback to default colored markers
      switch (assetPath) {
        case 'assets/markers/patient.png':
          return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
        case 'assets/markers/hospital.png':
          return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
        case 'assets/markers/ambulance.png':
          return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
        default:
          return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
      }
    }
  }

  /// Adds a marker to the map
  /// 
  /// [id] - Unique identifier for the marker
  /// [position] - LatLng position for the marker
  /// [iconType] - Type of icon ('patient', 'hospital', 'ambulance', 'default')
  /// [infoTitle] - Title for the info window
  /// [infoSnippet] - Snippet for the info window
  /// [onTap] - Callback when marker is tapped
  /// 
  /// Returns the MarkerId of the created marker
  Future<MarkerId> addMarker({
    required String id,
    required LatLng position,
    String iconType = 'default',
    String? infoTitle,
    String? infoSnippet,
    VoidCallback? onTap,
  }) async {
    final markerId = MarkerId(id);
    _markerIds[id] = markerId;
    
    final marker = Marker(
      markerId: markerId,
      position: position,
      icon: _markerIcons[iconType] ?? _markerIcons['default'] ?? BitmapDescriptor.defaultMarker,
      infoWindow: InfoWindow(
        title: infoTitle,
        snippet: infoSnippet,
      ),
      onTap: onTap,
    );
    
    _markers.add(marker);
    return markerId;
  }

  /// Removes a marker from the map
  /// 
  /// [id] - ID of the marker to remove
  void removeMarker(String id) {
    final markerId = _markerIds[id];
    if (markerId != null) {
      _markers.removeWhere((marker) => marker.markerId == markerId);
      _markerIds.remove(id);
    }
  }

  /// Updates the position of an existing marker
  /// 
  /// [id] - ID of the marker to update
  /// [newPos] - New LatLng position
  void updateMarkerPosition(String id, LatLng newPos) {
    final markerId = _markerIds[id];
    if (markerId != null) {
      final existingMarker = _markers.firstWhere(
        (marker) => marker.markerId == markerId,
        orElse: () => throw MapException('Marker with id $id not found'),
      );
      
      _markers.remove(existingMarker);
      
      final updatedMarker = existingMarker.copyWith(
        positionParam: newPos,
      );
      
      _markers.add(updatedMarker);
    }
  }

  /// Updates the icon of an existing marker
  /// 
  /// [id] - ID of the marker to update
  /// [iconType] - New icon type
  void updateMarkerIcon(String id, String iconType) {
    final markerId = _markerIds[id];
    if (markerId != null) {
      final existingMarker = _markers.firstWhere(
        (marker) => marker.markerId == markerId,
        orElse: () => throw MapException('Marker with id $id not found'),
      );
      
      _markers.remove(existingMarker);
      
      final updatedMarker = existingMarker.copyWith(
        iconParam: _markerIcons[iconType] ?? _markerIcons['default'] ?? BitmapDescriptor.defaultMarker,
      );
      
      _markers.add(updatedMarker);
    }
  }

  /// Draws a route between origin and destination
  /// 
  /// [origin] - Starting point
  /// [destination] - Ending point
  /// [routeId] - Optional ID for the route polyline
  /// [color] - Optional color for the route
  /// [width] - Optional width for the route
  /// 
  /// Returns the PolylineId of the created route
  Future<PolylineId> drawRoute(
    LatLng origin,
    LatLng destination, {
    String? routeId,
    Color color = const Color(0xFF2196F3),
    double width = 5.0,
  }) async {
    try {
      final routes = await NavigationService.getRouteOptions(
        origin: origin,
        destination: destination,
        includeAlternatives: false,
      );

      if (routes.isEmpty || routes.first.points.isEmpty) {
        throw MapException('No route geometry returned');
      }

      final directions = routes.first.points;
      
      final polylineId = PolylineId(routeId ?? 'route_${DateTime.now().millisecondsSinceEpoch}');
      final polyline = Polyline(
        polylineId: polylineId,
        color: color,
        width: width.toInt(),
        points: directions,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      );
      
      _polylines.add(polyline);
      return polylineId;
    } catch (e) {
      throw MapException('Failed to draw route: $e');
    }
  }

  /// Clears all routes from the map
  /// 
  /// [routeId] - Optional specific route ID to clear, if null clears all routes
  void clearRoute([String? routeId]) {
    if (routeId != null) {
      _polylines.removeWhere((polyline) => polyline.polylineId.value == routeId);
    } else {
      _polylines.clear();
    }
  }

  /// Draws a route polyline from precomputed points.
  PolylineId drawRouteFromPoints(
    List<LatLng> points, {
    String? routeId,
    Color color = const Color(0xFF2196F3),
    double width = 5.0,
    bool clearExistingRoutes = true,
  }) {
    if (points.isEmpty) {
      throw MapException('Cannot draw route from empty points list');
    }

    if (clearExistingRoutes) {
      _polylines.clear();
    }

    final polylineId = PolylineId(
      routeId ?? 'route_${DateTime.now().millisecondsSinceEpoch}',
    );

    final polyline = Polyline(
      polylineId: polylineId,
      color: color,
      width: width.toInt(),
      points: points,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
    );

    _polylines.add(polyline);
    return polylineId;
  }

  /// Computes map bounds for a list of points with small visual padding.
  LatLngBounds boundsForPoints(List<LatLng> points, {double pad = 0.002}) {
    if (points.isEmpty) {
      throw MapException('Cannot compute bounds for empty points list');
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat - pad, minLng - pad),
      northeast: LatLng(maxLat + pad, maxLng + pad),
    );
  }

  /// Animates the camera to a specific target
  /// 
  /// [target] - Target LatLng position
  /// [zoom] - Optional zoom level (default: 15)
  /// [bearing] - Optional camera bearing
  /// [tilt] - Optional camera tilt
  /// [duration] - Optional animation duration
  Future<void> animateCameraTo(
    LatLng target, {
    double zoom = 15.0,
    double bearing = 0.0,
    double tilt = 0.0,
    Duration duration = const Duration(seconds: 1),
  }) async {
    if (_googleMapController == null) {
      throw MapException('Map controller not initialized');
    }

    await _googleMapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: zoom,
          bearing: bearing,
          tilt: tilt,
        ),
      ),
    );
  }

  /// Moves the camera instantly to a specific target
  /// 
  /// [target] - Target LatLng position
  /// [zoom] - Optional zoom level (default: 15)
  /// [bearing] - Optional camera bearing
  /// [tilt] - Optional camera tilt
  Future<void> moveCameraTo(
    LatLng target, {
    double zoom = 15.0,
    double bearing = 0.0,
    double tilt = 0.0,
  }) async {
    if (_googleMapController == null) {
      throw MapException('Map controller not initialized');
    }

    await _googleMapController!.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: zoom,
          bearing: bearing,
          tilt: tilt,
        ),
      ),
    );
  }

  /// Switches between map types
  /// 
  /// [mapType] - The new map type to use
  void switchMapType(MapType mapType) {
    _currentMapType = mapType;
  }

  /// Toggles between normal and satellite map types
  void toggleMapType() {
    _currentMapType = _currentMapType == MapType.normal 
        ? MapType.satellite 
        : MapType.normal;
  }

  /// Adds multiple hospital markers to the map
  /// 
  /// [hospitals] - List of hospitals to add as markers
  /// [onTap] - Optional callback when a hospital marker is tapped
  Future<List<MarkerId>> addHospitalMarkers(
    List<HospitalModel> hospitals, {
    Function(HospitalModel)? onTap,
  }) async {
    final markerIds = <MarkerId>[];
    
    for (final hospital in hospitals) {
      final markerId = await addMarker(
        id: hospital.id,
        position: LatLng(hospital.lat, hospital.lng),
        iconType: 'hospital',
        infoTitle: hospital.name,
        infoSnippet: '${hospital.distanceText} • ${hospital.isAvailable ? 'Available' : 'Unavailable'}',
        onTap: onTap != null ? () => onTap(hospital) : null,
      );
      markerIds.add(markerId);
    }
    
    return markerIds;
  }

  /// Updates ambulance position in real-time
  /// 
  /// [ambulanceId] - ID of the ambulance marker
  /// [newPosition] - New position of the ambulance
  /// [bearing] - Optional bearing/direction of movement
  void updateAmbulancePosition(
    String ambulanceId,
    LatLng newPosition, {
    double bearing = 0.0,
  }) {
    updateMarkerPosition(ambulanceId, newPosition);
    
    // Optionally update bearing if you have heading information
    final markerId = _markerIds[ambulanceId];
    if (markerId != null) {
      final existingMarker = _markers.firstWhere(
        (marker) => marker.markerId == markerId,
        orElse: () => throw MapException('Ambulance marker with id $ambulanceId not found'),
      );
      
      _markers.remove(existingMarker);
      
      final updatedMarker = existingMarker.copyWith(
        positionParam: newPosition,
        rotationParam: bearing,
      );
      
      _markers.add(updatedMarker);
    }
  }

  /// Gets the current camera position
  Future<CameraPosition?> getCameraPosition() async {
    if (_googleMapController == null) {
      throw MapException('Map controller not initialized');
    }
    
    throw MapException('getCameraPosition is not available');
  }

  /// Gets the visible region of the map
  Future<LatLngBounds?> getVisibleRegion() async {
    if (_googleMapController == null) {
      throw MapException('Map controller not initialized');
    }
    
    return await _googleMapController!.getVisibleRegion();
  }

  /// Clears all markers from the map
  void clearMarkers() {
    _markers.clear();
    _markerIds.clear();
  }

  /// Clears all markers and routes from the map
  void clearAll() {
    _markers.clear();
    _polylines.clear();
    _markerIds.clear();
  }

  /// Disposes of the map controller
  void dispose() {
    _googleMapController = null;
    _markers.clear();
    _polylines.clear();
    _markerIds.clear();
    _markerIcons.clear();
  }
}
