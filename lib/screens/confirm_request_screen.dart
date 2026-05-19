import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/emergency_provider.dart';
import '../services/location_service.dart';

class ConfirmRequestScreen extends StatefulWidget {
  const ConfirmRequestScreen({super.key});

  @override
  State<ConfirmRequestScreen> createState() => _ConfirmRequestScreenState();
}

class _ConfirmRequestScreenState extends State<ConfirmRequestScreen> {
  Position? _currentPosition;
  bool _isLoadingLocation = true;
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    try {
      final position = await LocationService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _isLoadingLocation = false;
          _markers.add(
            Marker(
              markerId: const MarkerId('patient_location'),
              position: LatLng(position.latitude, position.longitude),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
              infoWindow: const InfoWindow(title: 'Your Location'),
            ),
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  Widget _buildTypeCard(BuildContext context, String title, IconData icon, Color iconColor) {
    final provider = context.watch<EmergencyProvider>();
    bool isSelected = provider.selectedEmergencyType == title;
    
    return GestureDetector(
      onTap: () => context.read<EmergencyProvider>().setEmergencyType(title),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmergencyProvider>();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: Theme.of(context).colorScheme.primary),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Icon(LucideIcons.mapPin, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Malawi Medical SOS',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey[200],
              child: Icon(LucideIcons.user, color: Colors.grey[600], size: 20),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Confirm Request',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Confirm your emergency details to dispatch help',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 24),

                // Interactive Map View
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.teal[50],
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _isLoadingLocation
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text('Fetching live location...', style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          )
                        : _currentPosition != null
                            ? GoogleMap(
                                initialCameraPosition: CameraPosition(
                                  target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                                  zoom: 15.0,
                                ),
                                markers: _markers,
                                myLocationEnabled: true,
                                myLocationButtonEnabled: true,
                                zoomControlsEnabled: false,
                                tiltGesturesEnabled: false,
                                rotateGesturesEnabled: false,
                              )
                            : Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(LucideIcons.map, color: Colors.teal[600], size: 48),
                                    const SizedBox(height: 8),
                                    const Text('Failed to load GPS coordinates', style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              ),
                  ),
                ),
                const SizedBox(height: 32),

                // Emergency Type Selector
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'SELECT EMERGENCY TYPE',
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.5,
                  children: [
                    _buildTypeCard(context, 'Accident', LucideIcons.car, Colors.red),
                    _buildTypeCard(context, 'Illness', LucideIcons.plusSquare, Theme.of(context).colorScheme.primary),
                    _buildTypeCard(context, 'Maternal', LucideIcons.user, Theme.of(context).colorScheme.primary),
                    _buildTypeCard(context, 'Other', LucideIcons.moreHorizontal, Colors.grey),
                  ],
                ),
                const SizedBox(height: 100), // Space for sticky button
              ],
            ),
          ),
          
          // Sticky Confirm Button
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: provider.state == EmergencyState.loading
                    ? null
                    : () async {
                        // Call provider to trigger emergency
                        final success = await context.read<EmergencyProvider>().triggerEmergency(context);
                        if (success && context.mounted) {
                          context.go('/tracking');
                        } else if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(context.read<EmergencyProvider>().errorMessage ?? 'Failed')),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: provider.state == EmergencyState.loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Confirm Request',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
