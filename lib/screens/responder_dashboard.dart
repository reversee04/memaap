import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../models/emergency_request_model.dart';
import '../models/user_model.dart';
import '../repositories/emergency_repository.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/responder_service.dart';
import '../widgets/request_tile.dart';
import '../controllers/map_controller.dart';
import '../services/auth_service.dart';

/// BLoC for managing responder dashboard state
class ResponderDashboardCubit extends Cubit<ResponderDashboardState> {
  ResponderDashboardCubit() : super(ResponderDashboardState.initial());

  StreamSubscription? _requestsSubscription;

  @override
  Future<void> close() {
    _requestsSubscription?.cancel();
    EmergencyRepository.stopPollingForRequests();
    return super.close();
  }

  /// Loads initial data and starts WebSocket listening + SQLite polling
  Future<void> initialize() async {
    emit(state.copyWith(isLoading: true));
    
    try {
      // Get current user
      final user = await _getCurrentUser();
      if (user == null) {
        emit(state.copyWith(
          isLoading: false,
          error: 'User not found',
        ));
        return;
      }

      // Load all requests (including local/mock alerts)
      final requests = await EmergencyRepository.getAllRequests();

      // Start listening for incoming emergency requests via WebSocket
      _listenForIncomingRequests(user.id);

      // Start SQLite polling every 3 seconds so we catch new requests
      // even when WebSocket is unavailable (offline / local dev mode)
      EmergencyRepository.startPollingForRequests((polledRequests) {
        if (!isClosed) {
          // Merge polled list with current state — keep the newest unique set
          final merged = {
            for (final r in [...polledRequests, ...state.requests]) r.id: r,
          }.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final hasNew = merged.length > state.requests.length ||
              merged.any((r) =>
                  r.status == EmergencyStatus.pending &&
                  !state.requests.any((old) => old.id == r.id));

          emit(state.copyWith(
            requests: merged,
            hasNewRequest: hasNew ? true : state.hasNewRequest,
          ));

          if (hasNew) {
            Future.delayed(const Duration(seconds: 4), () {
              if (!isClosed) emit(state.copyWith(hasNewRequest: false));
            });
          }
        }
      });
      
      emit(state.copyWith(
        isLoading: false,
        user: user,
        requests: requests,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to initialize dashboard: \$e',
      ));
    }
  }

  /// Gets the current authenticated user
  Future<UserModel?> _getCurrentUser() async {
    try {
      return await AuthService.getCurrentUser();
    } catch (e) {
      debugPrint('Failed to get authenticated responder: $e');
      return UserModel(
        id: 'responder_123',
        name: 'Officer John Banda',
        phone: '+265 999 123 456',
        role: 'responder',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
  }

  /// Listens for incoming emergency requests via WebSocket (best-effort)
  void _listenForIncomingRequests(String responderId) {
    try {
      _requestsSubscription?.cancel();
      _requestsSubscription = EmergencyRepository.watchRequest(responderId).listen(
        (request) {
          if (isClosed) return;
          final currentState = state;
          // Insert or update the request in the list
          final updated = [request, ...currentState.requests.where((r) => r.id != request.id)];
          updated.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          
          emit(currentState.copyWith(
            requests: updated,
            hasNewRequest: true,
          ));
          
          // Clear new request flag after a delay
          Future.delayed(const Duration(seconds: 3), () {
            if (!isClosed && state.requests.isNotEmpty) {
              emit(state.copyWith(hasNewRequest: false));
            }
          });
        },
        onError: (e) {
          // WebSocket failed — SQLite polling is the fallback, so just log
          debugPrint('WebSocket stream error (dashboard polling fallback active): \$e');
        },
      );
    } catch (e) {
      debugPrint('Failed to start WebSocket listener: \$e');
    }
  }

  /// Refreshes the requests list
  Future<void> refreshRequests() async {
    try {
      final requests = await EmergencyRepository.getAllRequests();
      
      emit(state.copyWith(
        isLoading: false,
        requests: requests,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to refresh requests: $e',
      ));
    }
  }

  /// Clears any error state
  void clearError() {
    emit(state.copyWith(error: null));
  }
}

/// State class for responder dashboard
class ResponderDashboardState {
  final bool isLoading;
  final List<EmergencyRequest> requests;
  final UserModel? user;
  final String? error;
  final bool hasNewRequest;

  const ResponderDashboardState({
    this.isLoading = false,
    this.requests = const [],
    this.user,
    this.error,
    this.hasNewRequest = false,
  });

  ResponderDashboardState copyWith({
    bool? isLoading,
    List<EmergencyRequest>? requests,
    UserModel? user,
    String? error,
    bool? hasNewRequest,
  }) {
    return ResponderDashboardState(
      isLoading: isLoading ?? this.isLoading,
      requests: requests ?? this.requests,
      user: user ?? this.user,
      error: error,
      hasNewRequest: hasNewRequest ?? this.hasNewRequest,
    );
  }

  const ResponderDashboardState.initial() : this();
}

/// Real-time responder dashboard with WebSocket-driven request list
class ResponderDashboard extends StatefulWidget {
  const ResponderDashboard({Key? key}) : super(key: key);

  @override
  State<ResponderDashboard> createState() => _ResponderDashboardState();
}

class _ResponderDashboardState extends State<ResponderDashboard> 
    with TickerProviderStateMixin {
  late ResponderDashboardCubit _cubit;
  int _currentIndex = 0;
  
  // Custom states
  String _selectedFilter = 'all'; // all, pending, active, completed
  bool _isOnlineDuty = true;
  LatLng _responderLocation = const LatLng(-15.786111, 35.005833); // Blantyre default
  MapController? _mapController;
  StreamSubscription<Position>? _locationSubscription;
  EmergencyRequest? _selectedMapRequest;

  // Pulse animation for Online status
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _cubit = ResponderDashboardCubit();
    _cubit.initialize();
    
    // Initialize status pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 4.0, end: 12.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initLocationListening();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _pulseController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  /// Listens to responder location and updates map coordinates in real-time
  Future<void> _initLocationListening() async {
    try {
      final hasPermission = await LocationService.requestPermission();
      if (hasPermission) {
        final currentPos = await LocationService.getCurrentLocation();
        if (currentPos != null) {
          setState(() {
            _responderLocation = LatLng(currentPos.latitude, currentPos.longitude);
          });
        }

        _locationSubscription = LocationService.getLocationStream(distanceFilter: 10)?.listen((position) {
          if (mounted) {
            setState(() {
              _responderLocation = LatLng(position.latitude, position.longitude);
              if (_mapController != null) {
                _mapController!.updateAmbulancePosition('responder_self', _responderLocation);
              }
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to load GPS location: $e');
    }
  }

  /// Toggles duty state
  Future<void> _toggleDutyState(bool isOnline, String responderId) async {
    setState(() {
      _isOnlineDuty = isOnline;
    });

    final success = await ResponderService.updateResponderAvailability(responderId, isOnline);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isOnline ? LucideIcons.shield : LucideIcons.shieldAlert,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Text(isOnline ? 'You are now ON ACTIVE DUTY' : 'You are now OFFLINE'),
            ],
          ),
          backgroundColor: isOnline ? const Color(0xFFE53935) : Colors.grey[800],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => _cubit,
      child: BlocBuilder<ResponderDashboardCubit, ResponderDashboardState>(
        builder: (context, state) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
            appBar: _buildAppBar(state),
            body: _buildBody(context, state),
            bottomNavigationBar: _buildBottomNavigationBar(),
          );
        },
      ),
    );
  }

  /// Builds custom premium app bar with status toggles
  PreferredSizeWidget _buildAppBar(ResponderDashboardState state) {
    final user = state.user;
    final responderName = user?.name ?? 'Officer John';
    final responderId = user?.id ?? 'responder_123';

    return AppBar(
      backgroundColor: const Color(0xFFE53935),
      elevation: 4,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.shield, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                responderName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            user?.phone ?? '+265 999 123 456',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white70,
            ),
          ),
        ],
      ),
      actions: [
        // Pulse duty indicator
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isOnlineDuty 
                    ? Colors.green.withOpacity(0.2) 
                    : Colors.grey.withOpacity(0.2),
              ),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isOnlineDuty ? Colors.greenAccent : Colors.grey,
                  boxShadow: _isOnlineDuty ? [
                    BoxShadow(
                      color: Colors.greenAccent,
                      blurRadius: _pulseAnimation.value,
                      spreadRadius: _pulseAnimation.value / 2,
                    )
                  ] : [],
                ),
              ),
            );
          },
        ),
        
        // Availability Toggle Text
        Text(
          _isOnlineDuty ? 'ACTIVE' : 'OFFLINE',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _isOnlineDuty ? Colors.white : Colors.white60,
          ),
        ),
        
        // Availability Switch
        Switch(
          value: _isOnlineDuty,
          onChanged: (val) => _toggleDutyState(val, responderId),
          activeColor: Colors.white,
          activeTrackColor: Colors.greenAccent,
          inactiveThumbColor: Colors.white70,
          inactiveTrackColor: Colors.red[800],
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// Builds the main body content
  Widget _buildBody(BuildContext context, ResponderDashboardState state) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE53935)),
        ),
      );
    }

    if (state.error != null) {
      return _buildErrorState(state.error!);
    }

    return IndexedStack(
      index: _currentIndex,
      children: [
        _buildRequestsTab(state),
        _buildMapTab(state),
        _buildProfileTab(state),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 1: ALERTS / REQUESTS LIST
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildRequestsTab(ResponderDashboardState state) {
    // Filter logic
    final filtered = state.requests.where((request) {
      if (_selectedFilter == 'pending') {
        return request.status == EmergencyStatus.pending;
      } else if (_selectedFilter == 'active') {
        return request.status == EmergencyStatus.accepted || request.status == EmergencyStatus.inProgress;
      } else if (_selectedFilter == 'completed') {
        return request.status == EmergencyStatus.completed;
      }
      return true; // all
    }).toList();

    return RefreshIndicator(
      color: const Color(0xFFE53935),
      onRefresh: () => _cubit.refreshRequests(),
      child: Column(
        children: [
          // Dynamic stats banner
          _buildStatsRowBanner(state),

          // Filters Row
          _buildFiltersRow(),

          // Requests list
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final request = filtered[index];
                      return _buildPremiumRequestTile(request, state);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRowBanner(ResponderDashboardState state) {
    final activeCount = state.requests.where((r) => r.isActive).length;
    final pendingCount = state.requests.where((r) => r.status == EmergencyStatus.pending).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.alertCircle, color: Color(0xFFE53935), size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                '$pendingCount Urgent SOS',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFE53935)),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$activeCount Active Dispatches',
              style: const TextStyle(color: Color(0xFF0033CC), fontSize: 11, fontWeight: FontWeight.bold),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFiltersRow() {
    final filterOptions = [
      {'key': 'all', 'label': 'All Alerts'},
      {'key': 'pending', 'label': 'Urgent SOS'},
      {'key': 'active', 'label': 'My Tasks'},
      {'key': 'completed', 'label': 'Resolved'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: filterOptions.map((opt) {
          final isSelected = _selectedFilter == opt['key'];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ChoiceChip(
              label: Text(opt['label']!),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedFilter = opt['key']!);
                }
              },
              selectedColor: const Color(0xFFE53935),
              disabledColor: Colors.white,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              elevation: isSelected ? 2 : 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? Colors.transparent : Colors.grey[300]!,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPremiumRequestTile(EmergencyRequest request, ResponderDashboardState state) {
    final severityColor = _getEmergencyColor(request.type);
    final isPending = request.status == EmergencyStatus.pending;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      elevation: isPending ? 3 : 1,
      shadowColor: isPending ? Colors.red.withOpacity(0.3) : Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isPending ? const Color(0xFFE53935).withOpacity(0.3) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: () => _openRequestDetail(request, state),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Emergency icon badge with left border color
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: severityColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getEmergencyIcon(request.type),
                  color: severityColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),

              // Patient content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          request.typeDisplayName,
                          style: TextStyle(
                            color: severityColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        _buildStatusBadge(request.status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'SOS ID: #${request.id.substring(request.id.length > 5 ? request.id.length - 5 : 0)} • patient ID: ${request.userId}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    if (request.description.isNotEmpty)
                      Text(
                        request.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(LucideIcons.mapPin, size: 12, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            request.address ?? 'GPS: ${request.latitude.toStringAsFixed(4)}, ${request.longitude.toStringAsFixed(4)}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(LucideIcons.clock, size: 12, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          request.timeAgo,
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(EmergencyStatus status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case EmergencyStatus.pending:
        bg = Colors.amber[50]!;
        fg = Colors.amber[800]!;
        label = 'Urgent SOS';
        break;
      case EmergencyStatus.accepted:
        bg = Colors.orange[50]!;
        fg = Colors.orange[850]!;
        label = 'En Route';
        break;
      case EmergencyStatus.inProgress:
        bg = Colors.blue[50]!;
        fg = Colors.blue[800]!;
        label = 'On Scene';
        break;
      case EmergencyStatus.completed:
        bg = Colors.green[50]!;
        fg = Colors.green[800]!;
        label = 'Resolved';
        break;
      case EmergencyStatus.cancelled:
        bg = Colors.grey[100]!;
        fg = Colors.grey[600]!;
        label = 'Cancelled';
        break;
      default:
        bg = Colors.grey[100]!;
        fg = Colors.grey[600]!;
        label = 'Expired';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 2: INTERACTIVE LIVE MAP
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildMapTab(ResponderDashboardState state) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _responderLocation,
            zoom: 14.0,
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: _mapController?.markers ?? {},
          polylines: _mapController?.polylines ?? {},
          onMapCreated: (gController) async {
            final mCtrl = MapController();
            await mCtrl.initialize(gController);
            setState(() {
              _mapController = mCtrl;
            });
            _updateMapMarkers(state);
          },
        ),

        // Map Control Overlays
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: _buildMapHeaderAlert(state),
        ),

        // Map Quick Details Sheet (when marker is tapped)
        if (_selectedMapRequest != null)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: _buildMapDetailCard(_selectedMapRequest!, state),
          ),

        // Quick GPS Re-center button
        Positioned(
          right: 16,
          bottom: _selectedMapRequest != null ? 220 : 16,
          child: FloatingActionButton(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFFE53935),
            onPressed: () {
              _mapController?.animateCameraTo(_responderLocation, zoom: 15);
            },
            child: const Icon(LucideIcons.navigation),
          ),
        ),
      ],
    );
  }

  Widget _buildMapHeaderAlert(ResponderDashboardState state) {
    final pendingCount = state.requests.where((r) => r.status == EmergencyStatus.pending).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          Icon(
            _isOnlineDuty ? LucideIcons.radio : LucideIcons.activity,
            color: _isOnlineDuty ? const Color(0xFFE53935) : Colors.grey,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isOnlineDuty 
                  ? 'Listening live for SOS requests ($pendingCount pending)' 
                  : 'You are currently offline. Go online to respond.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _isOnlineDuty ? Colors.black87 : Colors.grey[600],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMapDetailCard(EmergencyRequest request, ResponderDashboardState state) {
    final severityColor = _getEmergencyColor(request.type);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: severityColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  request.typeDisplayName,
                  style: TextStyle(color: severityColor, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              _buildStatusBadge(request.status),
              const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  setState(() {
                    _selectedMapRequest = null;
                    _mapController?.clearRoute();
                  });
                },
                icon: const Icon(LucideIcons.x, size: 18, color: Colors.grey),
              )
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Patient: ${request.userId}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            request.description.isNotEmpty ? request.description : 'No description provided.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openRequestDetail(request, state),
                  icon: const Icon(LucideIcons.externalLink, size: 14),
                  label: const Text('Full View'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE53935),
                    side: const BorderSide(color: Color(0xFFE53935)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // Draw active path on map
                    if (_mapController != null) {
                      _mapController!.clearRoute();
                      await _mapController!.drawRoute(
                        _responderLocation,
                        LatLng(request.latitude, request.longitude),
                        color: const Color(0xFF0033CC),
                        width: 5,
                      );
                      
                      // Animate between coordinates
                      double minLat = _responderLocation.latitude < request.latitude ? _responderLocation.latitude : request.latitude;
                      double maxLat = _responderLocation.latitude > request.latitude ? _responderLocation.latitude : request.latitude;
                      double minLng = _responderLocation.longitude < request.longitude ? _responderLocation.longitude : request.longitude;
                      double maxLng = _responderLocation.longitude > request.longitude ? _responderLocation.longitude : request.longitude;

                      _mapController!.controller?.animateCamera(
                        CameraUpdate.newLatLngBounds(
                          LatLngBounds(
                            southwest: LatLng(minLat - 0.002, minLng - 0.002),
                            northeast: LatLng(maxLat + 0.002, maxLng + 0.002),
                          ),
                          50,
                        ),
                      );
                    }
                  },
                  icon: const Icon(LucideIcons.navigation, size: 14),
                  label: const Text('Get Route'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0033CC),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  /// Refreshes all markers on Google Map
  Future<void> _updateMapMarkers(ResponderDashboardState state) async {
    try {
      if (_mapController == null) return;
      _mapController!.clearMarkers();

      // Add self responder marker
      await _mapController!.addMarker(
        id: 'responder_self',
        position: _responderLocation,
        iconType: 'ambulance',
        infoTitle: 'Your Ambulance (Self)',
        infoSnippet: _isOnlineDuty ? 'Active duty' : 'Offline',
      );

      // Add markers for all active SOS requests
      for (final req in state.requests) {
        if (req.status == EmergencyStatus.completed || req.status == EmergencyStatus.cancelled) continue;
        
        await _mapController!.addMarker(
          id: req.id,
          position: LatLng(req.latitude, req.longitude),
          iconType: 'patient',
          infoTitle: '${req.typeDisplayName} (${req.statusDisplayName})',
          infoSnippet: req.description,
          onTap: () {
            setState(() {
              _selectedMapRequest = req;
            });
          },
        );
      }
    } catch (e) {
      debugPrint('Failed to load map markers: $e');
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TAB 3: RESPONDER PROFILE & DISPATCH LOGS
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildProfileTab(ResponderDashboardState state) {
    final user = state.user;
    final totalDispatches = state.requests.where((r) => r.status == EmergencyStatus.completed).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Sleek glassmorphic card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE53935), Color(0xFFC62828)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  child: Text(
                    user != null && user.name.isNotEmpty ? user.name[0].toUpperCase() : 'O',
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'Officer John Banda',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'MEMAAP SENIOR PARAMEDIC',
                          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Agency ID: MEMAAP-BT-20593',
                        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Statistics Grid
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.1,
            children: [
              _buildStatCard('Lives Saved', '$totalDispatches', LucideIcons.heart, Colors.red),
              _buildStatCard('Response Rate', '98.5%', LucideIcons.activity, Colors.green),
              _buildStatCard('Duty Level', 'Lvl 4', LucideIcons.award, Colors.blue),
            ],
          ),
          const SizedBox(height: 20),

          // Dispatch history list
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Recent Dispatch History',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          _buildDispatchHistoryList(state),
          const SizedBox(height: 24),

          // Log out button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                context.go('/login');
              },
              icon: const Icon(LucideIcons.logOut),
              label: const Text('SIGN OUT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(color: Colors.grey[500], fontSize: 9, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDispatchHistoryList(ResponderDashboardState state) {
    final completed = state.requests.where((r) => r.status == EmergencyStatus.completed).toList();

    if (completed.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(LucideIcons.clipboard, color: Colors.grey[300], size: 40),
            const SizedBox(height: 8),
            Text('No dispatches completed yet.', style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: completed.length > 5 ? 5 : completed.length,
      itemBuilder: (context, index) {
        final req = completed[index];
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
                child: const Icon(LucideIcons.check, color: Colors.green, size: 14),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.typeDisplayName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      req.address ?? 'Blantyre SOS Hub',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                req.timeAgo,
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              )
            ],
          ),
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // INTERACTIVE WORKFLOW DETAIL SHEET (Accept ➔ Dispatch ➔ Complete)
  // ───────────────────────────────────────────────────────────────────────────
  void _openRequestDetail(EmergencyRequest request, ResponderDashboardState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final severityColor = _getEmergencyColor(request.type);
            final responderId = state.user?.id ?? 'responder_123';

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header Tags
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: severityColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          request.typeDisplayName,
                          style: TextStyle(color: severityColor, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusBadge(request.status),
                      const Spacer(),
                      Text(
                        request.timeAgo,
                        style: TextStyle(color: Colors.grey[500], fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Title details
                  Text(
                    'SOS Alert Details',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      request.description.isNotEmpty ? request.description : 'No additional details provided by patient.',
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Patient metadata
                  _buildMetaDetailRow(LucideIcons.user, 'Patient SOS ID', request.userId),
                  _buildMetaDetailRow(
                    LucideIcons.mapPin, 
                    'Emergency Address', 
                    request.address ?? 'Coordinates: ${request.latitude.toStringAsFixed(5)}, ${request.longitude.toStringAsFixed(5)}'
                  ),
                  _buildMetaDetailRow(
                    LucideIcons.phone, 
                    'Contact Number', 
                    '+265 888 765 432 (Simulated)'
                  ),
                  const SizedBox(height: 16),

                  // Progress workflow visualizer
                  const Divider(),
                  const SizedBox(height: 12),
                  const Text(
                    'SOS Dispatch Control Center',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 12),

                  // Dynamic action workflows based on status
                  _buildActionControls(request, responderId, setSheetState),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMetaDetailRow(IconData icon, String title, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 12.5),
                children: [
                  TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: val),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionControls(EmergencyRequest request, String responderId, StateSetter setSheetState) {
    if (request.status == EmergencyStatus.completed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.checkCircle2, color: Colors.green),
            SizedBox(width: 8),
            Text(
              'This emergency response has been resolved.',
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
            )
          ],
        ),
      );
    }

    if (request.status == EmergencyStatus.cancelled) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.xCircle, color: Colors.grey),
            SizedBox(width: 8),
            Text(
              'This alert was cancelled by the patient.',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12),
            )
          ],
        ),
      );
    }

    // Step 1: Pending SOS
    if (request.status == EmergencyStatus.pending) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: () async {
            // Close details modal
            Navigator.of(context).pop();
            
            // Accept SOS Flow
            final success = await ResponderService.acceptEmergencyRequest(
              context,
              request.id,
              responderId,
            );

            if (success) {
              _cubit.refreshRequests();
            }
          },
          icon: const Icon(LucideIcons.shieldCheck),
          label: const Text(
            'ACCEPT SOS ALERT',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE53935),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    // Step 2: Accepted (Paramedic is En Route)
    if (request.status == EmergencyStatus.accepted) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _callPatientNumber('+265888765432'),
              icon: const Icon(LucideIcons.phone),
              label: const Text('Call Patient'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE53935),
                side: const BorderSide(color: Color(0xFFE53935)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _updateEmergencyWorkflow(request, EmergencyStatus.inProgress, setSheetState),
              icon: const Icon(LucideIcons.truck),
              label: const Text('ARRIVED ON SCENE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0033CC),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          )
        ],
      );
    }

    // Step 3: Arrived / On Scene
    if (request.status == EmergencyStatus.inProgress) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _callPatientNumber('+265888765432'),
              icon: const Icon(LucideIcons.phone),
              label: const Text('Call dispatch'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey[700],
                side: BorderSide(color: Colors.grey[400]!),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _updateEmergencyWorkflow(request, EmergencyStatus.completed, setSheetState),
              icon: const Icon(LucideIcons.check),
              label: const Text('MARK RESOLVED'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          )
        ],
      );
    }

    return const SizedBox.shrink();
  }

  /// Calls telephone number
  Future<void> _callPatientNumber(String tel) async {
    final uri = Uri.parse('tel:$tel');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      debugPrint('Could not initiate phone call to patient');
    }
  }

  /// Steps forward in the emergency state machine
  Future<void> _updateEmergencyWorkflow(EmergencyRequest request, EmergencyStatus nextStatus, StateSetter setSheetState) async {
    try {
      final updated = await EmergencyRepository.updateRequestStatus(request.id, nextStatus);
      
      // Update modal bottom sheet state dynamically
      setSheetState(() {
        request = updated;
      });

      // Refresh list
      _cubit.refreshRequests();

      // Show toast
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(LucideIcons.checkCircle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Emergency status changed to: ${updated.statusDisplayName}'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // If completed, auto pop bottom sheet after a tiny delay
        if (nextStatus == EmergencyStatus.completed) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (Navigator.canPop(context)) {
              Navigator.of(context).pop();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) {
        setState(() {
          _currentIndex = index;
        });
      },
      selectedItemColor: const Color(0xFFE53935), // Signature emergency red color!
      unselectedItemColor: Colors.grey[500],
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(LucideIcons.list),
          label: 'SOS Alerts',
        ),
        BottomNavigationBarItem(
          icon: Icon(LucideIcons.navigation),
          label: 'SOS Map',
        ),
        BottomNavigationBarItem(
          icon: Icon(LucideIcons.user),
          label: 'My Account',
        ),
      ],
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.alertTriangle, size: 56, color: Color(0xFFE53935)),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _cubit.refreshRequests(),
              child: const Text('Try Again'),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.shieldAlert, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No active emergency alerts found',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Text(
              'New emergency signals from patients will appear here immediately.',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getEmergencyIcon(EmergencyType type) {
    switch (type) {
      case EmergencyType.medical:
        return LucideIcons.briefcase;
      case EmergencyType.accident:
        return LucideIcons.car;
      case EmergencyType.cardiac:
        return LucideIcons.heart;
      case EmergencyType.stroke:
        return LucideIcons.activity;
      case EmergencyType.trauma:
        return LucideIcons.shieldAlert;
      default:
        return LucideIcons.helpCircle;
    }
  }

  Color _getEmergencyColor(EmergencyType type) {
    switch (type) {
      case EmergencyType.medical:
        return const Color(0xFF26A69A); // Teal
      case EmergencyType.accident:
        return const Color(0xFFE53935); // Crimson
      case EmergencyType.cardiac:
        return const Color(0xFFEC407A); // Rose Pink
      case EmergencyType.stroke:
        return const Color(0xFFAB47BC); // Purple
      case EmergencyType.trauma:
        return const Color(0xFFFFB300); // Amber
      default:
        return Colors.grey;
    }
  }
}
