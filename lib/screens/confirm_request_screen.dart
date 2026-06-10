import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/emergency_provider.dart';
import '../services/location_service.dart';
import '../models/emergency_request_model.dart';
import '../repositories/emergency_repository.dart';

class ConfirmRequestScreen extends StatefulWidget {
  const ConfirmRequestScreen({super.key});

  @override
  State<ConfirmRequestScreen> createState() => _ConfirmRequestScreenState();
}

class _ConfirmRequestScreenState extends State<ConfirmRequestScreen>
    with SingleTickerProviderStateMixin {
  Position? _currentPosition;
  bool _isLoadingLocation = true;
  final Set<Marker> _markers = {};

  // GPS accuracy helpers
  double? _gpsAccuracy; // metres

  // Offline state
  bool _isOnline = true;
  int _queuedCount = 0;

  // Animation for offline banner
  late AnimationController _bannerController;
  late Animation<double> _bannerAnimation;

  @override
  void initState() {
    super.initState();
    _bannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _bannerAnimation = CurvedAnimation(
      parent: _bannerController,
      curve: Curves.easeOut,
    );
    _loadLocation();
    _checkConnectivity();
  }

  @override
  void dispose() {
    _bannerController.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    try {
      final position = await LocationService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _gpsAccuracy = position.accuracy;
          _isLoadingLocation = false;
          _markers.add(
            Marker(
              markerId: const MarkerId('patient_location'),
              position: LatLng(position.latitude, position.longitude),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueBlue,
              ),
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

  Future<void> _retryGps() async {
    setState(() {
      _isLoadingLocation = true;
      _gpsAccuracy = null;
    });
    await _loadLocation();
  }

  void _checkConnectivity() {
    setState(() {
      _isOnline = EmergencyRepository.isOnline;
      _queuedCount = EmergencyRepository.getQueuedCount();
    });
    if (!_isOnline) {
      _bannerController.forward();
    }
  }

  // ── Accuracy helpers ───────────────────────────────────────────────────────

  Color _accuracyColor() {
    if (_gpsAccuracy == null) return Colors.grey;
    if (_gpsAccuracy! < 10) return const Color(0xFF2E7D32); // green
    if (_gpsAccuracy! < 50) return const Color(0xFFF9A825); // yellow
    return const Color(0xFFD32F2F); // red
  }

  String _accuracyLabel() {
    if (_gpsAccuracy == null) return 'Locating…';
    if (_gpsAccuracy! < 10) return 'High accuracy (${_gpsAccuracy!.toStringAsFixed(0)} m)';
    if (_gpsAccuracy! < 50) {
      return 'Medium accuracy (${_gpsAccuracy!.toStringAsFixed(0)} m)';
    }
    return 'Low accuracy (${_gpsAccuracy!.toStringAsFixed(0)} m) – retry?';
  }

  IconData _accuracyIcon() {
    if (_gpsAccuracy == null) return LucideIcons.mapPin;
    if (_gpsAccuracy! < 10) return LucideIcons.mapPin;
    if (_gpsAccuracy! < 50) return LucideIcons.alertCircle;
    return LucideIcons.alertTriangle;
  }

  // ── Severity helpers ───────────────────────────────────────────────────────

  Color _severityColor(EmergencySeverity s) {
    switch (s) {
      case EmergencySeverity.critical:
        return const Color(0xFFD32F2F);
      case EmergencySeverity.urgent:
        return const Color(0xFFF57C00);
      case EmergencySeverity.nonUrgent:
        return const Color(0xFF2E7D32);
    }
  }

  IconData _presetIcon(String iconAsset) {
    switch (iconAsset) {
      case 'heartPulse':
        return LucideIcons.heartPulse;
      case 'brain':
        return LucideIcons.brain;
      case 'droplets':
        return LucideIcons.droplets;
      case 'wind':
        return LucideIcons.wind;
      case 'userX':
        return LucideIcons.userX;
      case 'alertCircle':
        return LucideIcons.alertCircle;
      case 'zap':
        return LucideIcons.zap;
      case 'activity':
        return LucideIcons.activity;
      case 'car':
        return LucideIcons.car;
      case 'user':
        return LucideIcons.user;
      default:
        return LucideIcons.moreHorizontal;
    }
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _buildOfflineBanner() {
    return FadeTransition(
      opacity: _bannerAnimation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF57C00), Color(0xFFE65100)],
          ),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.wifiOff, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _queuedCount > 0
                    ? 'Offline — $_queuedCount request(s) queued for sync'
                    : 'You are offline — your request will sync when connected',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsAccuracyBadge() {
    final color = _accuracyColor();
    final label = _accuracyLabel();
    final icon = _accuracyIcon();
    final isLowAccuracy = _gpsAccuracy != null && _gpsAccuracy! >= 50;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isLowAccuracy) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _retryGps,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Retry GPS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeveritySelector(EmergencyProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SEVERITY LEVEL',
          style: TextStyle(
            color: Colors.grey[700],
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: EmergencySeverity.values.map((s) {
            final isSelected = provider.selectedSeverity == s;
            final color = _severityColor(s);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => provider.setSeverity(s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? color : color.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: color.withOpacity(isSelected ? 1 : 0.3),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          s == EmergencySeverity.critical
                              ? LucideIcons.alertOctagon
                              : s == EmergencySeverity.urgent
                                  ? LucideIcons.alertTriangle
                                  : LucideIcons.info,
                          color: isSelected ? Colors.white : color,
                          size: 18,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.displayName,
                          style: TextStyle(
                            color: isSelected ? Colors.white : color,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPresetCard(
    BuildContext context,
    QuickEmergencyPreset preset,
    EmergencyProvider provider,
  ) {
    final isSelected = provider.selectedType == preset.type;
    final color = _severityColor(preset.severity);
    final icon = _presetIcon(preset.iconAsset);

    return GestureDetector(
      onTap: () {
        provider.selectPreset(preset);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? color.withOpacity(0.15)
                  : Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                // Severity badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 1,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    preset.severity.displayName.toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              preset.type.typeDisplayName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isSelected ? color : Colors.black87,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                height: 3,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedPresetDetails(EmergencyProvider provider) {
    if (provider.presetDescription == null ||
        provider.presetDescription!.isEmpty) {
      return const SizedBox.shrink();
    }

    final color = _severityColor(provider.selectedSeverity);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.clipboardList, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              provider.presetDescription!,
              style: TextStyle(
                color: Colors.grey[800],
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmergencyProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            LucideIcons.arrowLeft,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Icon(
              LucideIcons.mapPin,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
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
          Column(
            children: [
              // Offline banner
              if (!_isOnline) _buildOfflineBanner(),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Confirm Emergency',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Select the type and confirm to dispatch help',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── MAP ──────────────────────────────────────────────
                      Container(
                        height: 180,
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
                                      Text(
                                        'Fetching live location…',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                )
                              : _currentPosition != null
                                  ? GoogleMap(
                                      initialCameraPosition: CameraPosition(
                                        target: LatLng(
                                          _currentPosition!.latitude,
                                          _currentPosition!.longitude,
                                        ),
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
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            LucideIcons.map,
                                            color: Colors.teal[600],
                                            size: 48,
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'Failed to load GPS coordinates',
                                            style: TextStyle(color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                        ),
                      ),

                      // GPS accuracy badge
                      if (!_isLoadingLocation)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _buildGpsAccuracyBadge(),
                        ),

                      const SizedBox(height: 24),

                      // ── QUICK TYPE GRID ─────────────────────────────────
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
                      const SizedBox(height: 12),

                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.9,
                        ),
                        itemCount: kQuickEmergencyPresets.length,
                        itemBuilder: (context, i) => _buildPresetCard(
                          context,
                          kQuickEmergencyPresets[i],
                          provider,
                        ),
                      ),

                      // ── SELECTED PRESET INFO ──────────────────────────
                      _buildSelectedPresetDetails(provider),

                      const SizedBox(height: 24),

                      // ── SEVERITY SELECTOR ─────────────────────────────
                      _buildSeveritySelector(provider),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── STICKY CONFIRM BUTTON ────────────────────────────────────────
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
                        debugPrint(
                          '[ConfirmRequestScreen] Confirm button pressed',
                        );
                        final success = await context
                            .read<EmergencyProvider>()
                            .triggerEmergency(context);
                        if (!success && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                context.read<EmergencyProvider>().errorMessage ??
                                    'Failed',
                              ),
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _severityColor(provider.selectedSeverity),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
                child: provider.state == EmergencyState.loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            provider.selectedSeverity ==
                                    EmergencySeverity.critical
                                ? LucideIcons.alertOctagon
                                : LucideIcons.send,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Confirm ${provider.selectedSeverity.displayName} Emergency',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
