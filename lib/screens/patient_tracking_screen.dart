import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/emergency_request_model.dart';
import '../repositories/emergency_repository.dart';
import '../services/auth_service.dart';
import 'tracking_screen.dart';

class PatientTrackingScreen extends StatefulWidget {
  const PatientTrackingScreen({super.key});

  @override
  State<PatientTrackingScreen> createState() => _PatientTrackingScreenState();
}

class _PatientTrackingScreenState extends State<PatientTrackingScreen> {
  late Future<EmergencyRequest?> _activeRequestFuture;

  @override
  void initState() {
    super.initState();
    _activeRequestFuture = _loadActiveRequest();
  }

  Future<EmergencyRequest?> _loadActiveRequest() async {
    final user = await AuthService.getCurrentUser();
    if (user == null) return null;

    final requests = await EmergencyRepository.getUserRequests(
      user.id,
      limit: 20,
    );

    for (final request in requests) {
      if (request.isActive) return request;
    }

    return null;
  }

  void _refresh() {
    setState(() {
      _activeRequestFuture = _loadActiveRequest();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EmergencyRequest?>(
      future: _activeRequestFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return _PatientTrackingEmptyState(
            title: 'Tracking unavailable',
            message: 'We could not load your emergency tracking right now.',
            actionLabel: 'Try Again',
            onAction: _refresh,
          );
        }

        final activeRequest = snapshot.data;
        if (activeRequest == null) {
          return _PatientTrackingEmptyState(
            title: 'No active emergency',
            message:
                'Your patient tracking page will appear here after you send an emergency request.',
            actionLabel: 'Start Request',
            onAction: () => context.go('/home/confirm'),
          );
        }

        return TrackingScreen(requestId: activeRequest.id);
      },
    );
  }
}

class _PatientTrackingEmptyState extends StatelessWidget {
  const _PatientTrackingEmptyState({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Tracking'),
        backgroundColor: const Color(0xFF0033CC),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF0033CC).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.near_me,
                  color: Color(0xFF0033CC),
                  size: 34,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0033CC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(actionLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
