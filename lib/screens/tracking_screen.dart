import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../models/emergency_request_model.dart';
import '../models/user_model.dart';
import '../providers/call_provider.dart';
import '../services/emergency_tracking_service.dart';
import '../services/emergency_service.dart';
import '../services/location_service.dart';
import '../controllers/map_controller.dart';
import '../widgets/status_stepper.dart';

/// Patient-facing tracking screen after submitting emergency request
/// 
/// Shows animated status stepper, live map with responder tracking,
/// ETA countdown, and options to cancel or call responder.
class TrackingScreen extends StatefulWidget {
  final String requestId;

  const TrackingScreen({
    Key? key,
    required this.requestId,
  }) : super(key: key);

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> 
    with TickerProviderStateMixin {
  EmergencyRequest? _currentRequest;
  StreamSubscription<EmergencyRequest>? _trackingSubscription;
  MapController? _mapController;
  bool _isReconnecting = false;
  Timer? _etaTimer;
  Duration? _remainingTime;

  @override
  void initState() {
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
        title: const Text('Emergency Tracking'),
        backgroundColor: Colors.red,
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
          ? _buildLoadingState()
          : _buildTrackingContent(),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  /// Starts tracking of emergency request
  Future<void> _startTracking() async {
    try {
      _trackingSubscription = EmergencyTrackingService.trackEmergencyRequest(widget.requestId)
          .listen(
            _onRequestUpdate,
            onError: _onTrackingError,
          );
    } catch (e) {
      debugPrint('Failed to start tracking: $e');
    }
  }

  /// Handles request updates from tracking service
  void _onRequestUpdate(EmergencyRequest request) {
    setState(() {
      _currentRequest = request;
      _isReconnecting = false;
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
    }
  }

  /// Builds loading state
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height:16),
          Text('Loading emergency tracking...'),
        ],
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
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(16),
            child: StatusStepper(
              currentStatus: _currentRequest!.status,
              isAnimated: true,
            ),
          ),
        ),
        
        // Map view
        Expanded(
          flex: 5,
          child: _buildMapView(),
        ),
        
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
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
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
                target: LatLng(_currentRequest!.latitude, _currentRequest!.longitude),
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
          const Icon(
            Icons.access_time,
            color: Colors.white,
            size: 20,
          ),
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
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
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

  /// Updates map markers
  Future<void> _updateMapMarkers(EmergencyRequest request) async {
    try {
      if (_mapController == null) return;

      // Clear existing markers
      _mapController!.clearMarkers();
      _mapController!.clearRoute();

      // Add patient marker (static)
      await _mapController!.addMarker(
        id: 'patient',
        position: LatLng(request.latitude, request.longitude),
        iconType: 'patient',
        infoTitle: 'Your Location',
        infoSnippet: request.typeDisplayName,
      );

      // Add responder marker (live)
      if (request.hasResponder) {
        // In a real implementation, you'd get responder's live location
        // For now, we'll add a marker near the patient
        final responderLatLng = LatLng(
          request.latitude + 0.003, // Slight offset for visibility
          request.longitude + 0.003,
        );
        await _mapController!.addMarker(
          id: 'responder',
          position: responderLatLng,
          iconType: 'ambulance',
          infoTitle: request.responderName ?? 'Responder',
          infoSnippet: 'En Route',
        );

        // Draw route
        await _mapController!.drawRoute(
          responderLatLng,
          LatLng(request.latitude, request.longitude),
          routeId: 'route',
          color: Colors.blue,
          width: 4.0,
        );

        // Animate camera to fit both markers
        double minLat = request.latitude < responderLatLng.latitude ? request.latitude : responderLatLng.latitude;
        double maxLat = request.latitude > responderLatLng.latitude ? request.latitude : responderLatLng.latitude;
        double minLng = request.longitude < responderLatLng.longitude ? request.longitude : responderLatLng.longitude;
        double maxLng = request.longitude > responderLatLng.longitude ? request.longitude : responderLatLng.longitude;

        LatLngBounds bounds = LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        );
        
        await _mapController!.controller?.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 50.0),
        );
      } else {
        // If no responder yet, center map on patient's coordinate
        await _mapController!.animateCameraTo(
          LatLng(request.latitude, request.longitude),
          zoom: 15.0,
        );
      }

      if (mounted) {
        setState(() {}); // Trigger redraw
      }
    } catch (e) {
      debugPrint('Failed to update map markers: $e');
    }
  }

  /// Calls the responder
  Future<void> _callResponder() async {
    if (_currentRequest?.hasResponder != true || _currentRequest == null) return;

    final callProvider = context.read<CallProvider>();
    await callProvider.initialize();
    await callProvider.startCall(_currentRequest!.id);

    if (!mounted) return;

    if (callProvider.state == CallUiState.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(callProvider.errorMessage ?? 'Failed to start call'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    context.push('/call', extra: {
      'title': 'Call with Responder',
    });
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
      await EmergencyService.cancelEmergencyRequest(context, _currentRequest!.id);
    }
  }

  /// Navigates to review screen when request is resolved
  void _navigateToReviewScreen() {
    // This would navigate to your review screen
    // context.go('/review', extra: {'requestId': widget.requestId});
    debugPrint('Navigate to review screen for request: ${widget.requestId}');
  }
}
