import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/emergency_request_model.dart';
import '../services/emergency_tracking_service.dart';
import '../services/emergency_service.dart';
import '../controllers/map_controller.dart';
import '../widgets/status_stepper.dart';

/// Patient-facing tracking screen after submitting emergency request
///
/// Shows animated status stepper, live map with responder tracking,
/// ETA countdown, and options to cancel or call responder.
class TrackingScreen extends StatefulWidget {
  final String requestId;

  const TrackingScreen({Key? key, required this.requestId}) : super(key: key);

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin {
  EmergencyRequest? _currentRequest;
  StreamSubscription<EmergencyRequest>? _trackingSubscription;
  MapController? _mapController;
  bool _isReconnecting = false;
  String? _trackingError;
  Timer? _etaTimer;

  @override
  void initState() {
    debugPrint(
      '[TrackingScreen] initState called with requestId: ${widget.requestId}',
    );
    if (widget.requestId.isEmpty) {
      debugPrint('[TrackingScreen] ERROR: requestId is empty!');
    }
    super.initState();
    _startTracking();
  }

  @override
  void dispose() {
    _trackingSubscription?.cancel();
    _etaTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Tracking'),
        backgroundColor: const Color(0xFF0033CC),
        foregroundColor: Colors.white,
        actions: [
          if (_currentRequest?.status == EmergencyStatus.pending)
            IconButton(
              onPressed: _cancelRequest,
              icon: const Icon(Icons.cancel),
              tooltip: 'Cancel Request',
            ),
        ],
      ),
      body: _currentRequest == null
          ? _trackingError == null
                ? _buildLoadingState()
                : _buildErrorState()
          : _buildTrackingContent(),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  /// Starts tracking of emergency request
  Future<void> _startTracking() async {
    try {
      _trackingSubscription = EmergencyTrackingService.trackEmergencyRequest(
        widget.requestId,
      ).listen(_onRequestUpdate, onError: _onTrackingError);
    } catch (e) {
      debugPrint('Failed to start tracking: $e');
    }
  }

  /// Handles request updates from tracking service
  void _onRequestUpdate(EmergencyRequest request) {
    setState(() {
      _currentRequest = request;
      _isReconnecting = false;
      _trackingError = null;
    });

    // Update map if available
    if (_mapController != null) {
      _updateMapMarkers(request);
    }

    // Check if request is resolved
    if (request.status == EmergencyStatus.completed) {
      _navigateToReviewScreen();
    }
  }

  /// Handles tracking errors
  void _onTrackingError(dynamic error) {
    if (error == 'RECONNECTING') {
      setState(() {
        _isReconnecting = true;
      });
    } else {
      debugPrint('Tracking error: $error');
      setState(() {
        _trackingError = error.toString();
      });
    }
  }

  /// Builds loading state
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading emergency tracking...'),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Unable to load emergency tracking',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _trackingError ?? 'Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds main tracking content
  Widget _buildTrackingContent() {
    if (_currentRequest == null) return const SizedBox.shrink();

    return Column(
      children: [
        // Reconnecting banner
        if (_isReconnecting) _buildReconnectingBanner(),

        // Status stepper
        Expanded(
          flex: 4,
          child: Container(
            padding: const EdgeInsets.all(5),
            child: StatusStepper(
              currentStatus: _currentRequest!.status,
              isAnimated: true,
            ),
          ),
        ),

        // Map view
        Expanded(flex: 5, child: _buildMapView()),

        // Bottom sheet with responder info
        _buildBottomSheet(),
      ],
    );
  }

  /// Builds reconnecting banner
  Widget _buildReconnectingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange,
      child: Row(
        children: [
          const Icon(Icons.sync, color: Colors.white),
          const SizedBox(width: 8),
          const Text(
            'Reconnecting to tracking service...',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds map view
  Widget _buildMapView() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.teal[50],
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(
                  _currentRequest!.latitude,
                  _currentRequest!.longitude,
                ),
                zoom: 15.0,
              ),
              markers: _mapController?.markers ?? {},
              polylines: _mapController?.polylines ?? {},
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              tiltGesturesEnabled: false,
              rotateGesturesEnabled: false,
              onMapCreated: (controller) async {
                final mapCtrl = MapController();
                await mapCtrl.initialize(controller);
                setState(() {
                  _mapController = mapCtrl;
                });
                _updateMapMarkers(_currentRequest!);
              },
            ),

            // ETA countdown overlay
            if (_currentRequest?.status == EmergencyStatus.inProgress)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: _buildETACountdown(),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds ETA countdown
  Widget _buildETACountdown() {
    if (_currentRequest?.estimatedArrivalMinutes == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.access_time, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            'ETA: ${_currentRequest!.estimatedArrivalText}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds bottom sheet with responder information
  Widget _buildBottomSheet() {
    if (_currentRequest == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Responder information
          if (_currentRequest!.hasResponder) ...[
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentRequest!.responderName ?? 'Responder',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (_currentRequest!.estimatedArrivalMinutes != null)
                        Text(
                          'Arriving in ${_currentRequest!.estimatedArrivalText}',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Hospital information
          if (_currentRequest!.hasResponder) ...[
            Row(
              children: [
                const Icon(Icons.local_hospital, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  'Assigned Hospital: Central Hospital',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Contact information
          if (_currentRequest!.hasResponder) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _callResponder,
                    icon: const Icon(Icons.phone),
                    label: const Text('Call Responder'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _shareLocation,
                    icon: const Icon(Icons.share),
                    label: const Text('Share Location'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Cancel button (only for pending requests)
          if (_currentRequest!.status == EmergencyStatus.pending) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _cancelRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Cancel Emergency Request'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Builds floating action button
  Widget? _buildFloatingActionButton() {
    if (_currentRequest?.hasResponder != true) return null;

    return FloatingActionButton.extended(
      onPressed: _callResponder,
      backgroundColor: Colors.green,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.phone),
      label: const Text('Call'),
    );
  }

  /// Updates map markers based on the latest request state.
  ///
  /// Shows patient pin at their emergency location and the ambulance at
  /// the responder's real-time GPS coordinates (from SQLite polling).
  Future<void> _updateMapMarkers(EmergencyRequest request) async {
    try {
      if (_mapController == null) return;

      // Clear existing markers and route
      _mapController!.clearMarkers();
      _mapController!.clearRoute();

      // Patient marker — always static at the reported emergency location
      await _mapController!.addMarker(
        id: 'patient',
        position: LatLng(request.latitude, request.longitude),
        iconType: 'patient',
        infoTitle: 'Your Location',
        infoSnippet: request.typeDisplayName,
      );

      // Responder / ambulance marker — use live GPS from database when available
      if (request.hasResponder) {
        final LatLng responderLatLng;
        final bool hasRealLocation =
            request.responderLat != null && request.responderLng != null;

        if (hasRealLocation) {
          // Use the actual GPS position broadcast by the responder
          responderLatLng = LatLng(
            request.responderLat!,
            request.responderLng!,
          );
        } else {
          // Fallback: show a placeholder marker near the patient until
          // the responder starts broadcasting their location
          responderLatLng = LatLng(
            request.latitude + 0.003,
            request.longitude + 0.003,
          );
        }

        await _mapController!.addMarker(
          id: 'responder',
          position: responderLatLng,
          iconType: 'ambulance',
          infoTitle: request.responderName ?? 'Responder',
          infoSnippet: hasRealLocation ? 'Live location' : 'Locating…',
        );

        // Draw route from responder to patient
        await _mapController!.drawRoute(
          responderLatLng,
          LatLng(request.latitude, request.longitude),
          routeId: 'route',
          color: Colors.blue,
          width: 4.0,
        );

        // Animate camera to fit both markers
        final double minLat = request.latitude < responderLatLng.latitude
            ? request.latitude
            : responderLatLng.latitude;
        final double maxLat = request.latitude > responderLatLng.latitude
            ? request.latitude
            : responderLatLng.latitude;
        final double minLng = request.longitude < responderLatLng.longitude
            ? request.longitude
            : responderLatLng.longitude;
        final double maxLng = request.longitude > responderLatLng.longitude
            ? request.longitude
            : responderLatLng.longitude;

        // Add a small padding so markers are not on the edge
        await _mapController!.controller?.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLat - 0.001, minLng - 0.001),
              northeast: LatLng(maxLat + 0.001, maxLng + 0.001),
            ),
            60.0,
          ),
        );
      } else {
        // No responder yet — center on patient's location
        await _mapController!.animateCameraTo(
          LatLng(request.latitude, request.longitude),
          zoom: 15.0,
        );
      }

      if (mounted) {
        setState(() {}); // Trigger marker redraw
      }
    } catch (e) {
      debugPrint('Failed to update map markers: \$e');
    }
  }

  /// Calls the responder
  Future<void> _callResponder() async {
    if (_currentRequest?.hasResponder != true) return;

    // In a real implementation, you'd get responder's phone number
    // For now, we'll use a mock number
    final phoneNumber = '+2651234567';

    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      debugPrint('Could not launch phone dialer');
    }
  }

  /// Shares current location
  Future<void> _shareLocation() async {
    if (_currentRequest == null) return;

    final locationUrl = _currentRequest!.mapsUrl;
    final uri = Uri.parse(locationUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      debugPrint('Could not share location');
    }
  }

  /// Cancels the emergency request
  Future<void> _cancelRequest() async {
    if (_currentRequest == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Emergency Request'),
        content: const Text(
          'Are you sure you want to cancel this emergency request? '
          'This will notify the assigned responder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await EmergencyService.cancelEmergencyRequest(
        context,
        _currentRequest!.id,
      );
    }
  }

  /// Navigates to review screen when request is resolved
  void _navigateToReviewScreen() {
    // This would navigate to your review screen
    // context.go('/review', extra: {'requestId': widget.requestId});
    debugPrint('Navigate to review screen for request: ${widget.requestId}');
  }
}
