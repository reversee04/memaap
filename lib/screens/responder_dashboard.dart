import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/emergency_request_model.dart';
import '../models/user_model.dart';
import '../repositories/emergency_repository.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
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
    return super.close();
  }

  /// Loads initial data and starts WebSocket listening
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

      // Start listening for incoming emergency requests
      _listenForIncomingRequests(user.id);
      
      emit(state.copyWith(
        isLoading: false,
        user: user,
        requests: requests,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: 'Failed to initialize dashboard: $e',
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
        name: 'John Responder',
        phone: '+2651234567',
        role: 'responder',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
  }

  /// Listens for incoming emergency requests via WebSocket
  void _listenForIncomingRequests(String responderId) {
    _requestsSubscription?.cancel();
    _requestsSubscription = EmergencyRepository.watchRequest(responderId).listen(
      (request) {
        final currentState = state;
        final updatedRequests = [request, ...currentState.requests];
        
        // Sort by newest first
        updatedRequests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        
        emit(currentState.copyWith(
          requests: updatedRequests,
          hasNewRequest: true,
        ));
        
        // Clear new request flag after a delay
        Future.delayed(const Duration(seconds: 3), () {
          if (state.requests.isNotEmpty) {
            emit(state.copyWith(hasNewRequest: false));
          }
        });
      },
    );
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
/// 
/// Displays emergency requests in an animated list with live updates,
/// map markers, and bottom navigation for Mobile Emergency Medical Assistance App.
class ResponderDashboard extends StatefulWidget {
  const ResponderDashboard({Key? key}) : super(key: key);

  @override
  State<ResponderDashboard> createState() => _ResponderDashboardState();
}

class _ResponderDashboardState extends State<ResponderDashboard> 
    with TickerProviderStateMixin, SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ResponderDashboardCubit _cubit;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cubit = ResponderDashboardCubit();
    _cubit.initialize();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocProvider(
        create: (context) => _cubit,
        child: BlocBuilder<ResponderDashboardCubit, ResponderDashboardState>(
          builder: (context, state) {
            return _buildBody(context, state);
          },
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  /// Builds the main body content
  Widget _buildBody(BuildContext context, ResponderDashboardState state) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (state.error != null) {
      return _buildErrorState(state.error!);
    }

    if (state.requests.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        // Header with new request indicator
        _buildHeader(state),
        
        // Request list, map view, or profile view
        Expanded(
          child: IndexedStack(
            index: _currentIndex,
            children: [
              _buildRequestsList(state),
              _buildMapView(state),
              _buildProfileView(state.user),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds the header with new request indicator
  Widget _buildHeader(ResponderDashboardState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Responder Dashboard',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${state.requests.length} Active Requests',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          
          // New request indicator
          if (state.hasNewRequest)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.notifications_active,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'New Request',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the requests list view
  Widget _buildRequestsList(ResponderDashboardState state) {
    return RefreshIndicator(
      onRefresh: () => _cubit.refreshRequests(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.requests.length,
        itemBuilder: (context, index) {
          final request = state.requests[index];
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: RequestTile(
              request: request,
              onTap: () => _openRequestDetail(request),
            ),
          );
        },
      ),
    );
  }

  /// Builds the map view
  Widget _buildMapView(ResponderDashboardState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'Live Map View',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  'Map view would be implemented here\nwith Google Maps integration',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the profile view
  Widget _buildProfileView(UserModel? user) {
    if (user == null) {
      return const Center(
        child: Text('User not found'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.blue,
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : 'R',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            user.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            user.phone,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Role: ${user.role}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  /// Builds error state
  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              error,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _cubit.clearError(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds empty state
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No active emergency requests',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'New requests will appear here when available',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds bottom navigation bar
  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) {
        setState(() {
          _currentIndex = index;
        });
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.list),
          label: 'Requests',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.map),
          label: 'Map',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }

  /// Opens request detail screen with interactive bottom sheet actions
  void _openRequestDetail(EmergencyRequest request) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24),
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
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red[100]!),
                        ),
                        child: Text(
                          request.type.typeDisplayName,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          request.statusDisplayName.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Emergency Details',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    request.description.isNotEmpty ? request.description : 'No description provided.',
                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          request.address ?? 'GPS: ${request.latitude.toStringAsFixed(5)}, ${request.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Update Alert Status',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatusActionButton(
                          context,
                          label: 'Accept',
                          status: EmergencyStatus.accepted,
                          currentStatus: request.status,
                          color: Colors.orange,
                          onPressed: () => _updateStatusAndRefresh(request.id, EmergencyStatus.accepted),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusActionButton(
                          context,
                          label: 'Dispatch',
                          status: EmergencyStatus.inProgress,
                          currentStatus: request.status,
                          color: Colors.blue,
                          onPressed: () => _updateStatusAndRefresh(request.id, EmergencyStatus.inProgress),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusActionButton(
                          context,
                          label: 'Complete',
                          status: EmergencyStatus.completed,
                          currentStatus: request.status,
                          color: Colors.green,
                          onPressed: () => _updateStatusAndRefresh(request.id, EmergencyStatus.completed),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusActionButton(
    BuildContext context, {
    required String label,
    required EmergencyStatus status,
    required EmergencyStatus currentStatus,
    required Color color,
    required VoidCallback onPressed,
  }) {
    final isActive = currentStatus == status;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? color : Colors.grey[200],
        foregroundColor: isActive ? Colors.white : Colors.black87,
        elevation: isActive ? 2 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Text(label),
    );
  }

  Future<void> _updateStatusAndRefresh(String id, EmergencyStatus status) async {
    try {
      await EmergencyRepository.updateRequestStatus(id, status);
      Navigator.of(context).pop();
      _cubit.refreshRequests();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Emergency status updated to ${status.name}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
