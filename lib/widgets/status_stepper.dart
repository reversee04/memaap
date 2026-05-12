import 'package:flutter/material.dart';
import '../models/emergency_request_model.dart';

/// Widget that displays animated status stepper for emergency requests
/// 
/// Shows progression: PENDING -> ACCEPTED -> EN_ROUTE -> ARRIVED
/// with smooth animations and icons for Mobile Emergency Medical Assistance App.
class StatusStepper extends StatefulWidget {
  final EmergencyStatus currentStatus;
  final bool isAnimated;

  const StatusStepper({
    Key? key,
    required this.currentStatus,
    this.isAnimated = true,
  }) : super(key: key);

  @override
  State<StatusStepper> createState() => _StatusStepperState();
}

class _StatusStepperState extends State<StatusStepper> 
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late List<Animation<double>> _stepAnimations;

  final List<EmergencyStatus> _statusOrder = [
    EmergencyStatus.pending,
    EmergencyStatus.accepted,
    EmergencyStatus.inProgress,
    EmergencyStatus.completed,
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _stepAnimations = List.generate(
      _statusOrder.length,
      (index) => Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(
            index * 0.2,
            (index + 1) * 0.2,
            curve: Curves.easeInOut,
          ),
        ),
      ),
    );

    if (widget.isAnimated) {
      _animationController.forward();
    } else {
      _animationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(StatusStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.currentStatus != widget.currentStatus) {
      _animationController.reset();
      _animationController.forward();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Status steps
          Row(
            children: List.generate(_statusOrder.length, (index) {
              final status = _statusOrder[index];
              final isActive = _getStepIndex(widget.currentStatus) >= index;
              final isCurrent = status == widget.currentStatus;
              
              return Expanded(
                child: _buildStatusStep(
                  status,
                  isActive,
                  isCurrent,
                  index,
                ),
              );
            }),
          ),
          
          // Progress line
          const SizedBox(height: 16),
          _buildProgressBar(),
        ],
      ),
    );
  }

  /// Builds individual status step
  Widget _buildStatusStep(
    EmergencyStatus status,
    bool isActive,
    bool isCurrent,
    int index,
  ) {
    return AnimatedBuilder(
      animation: _stepAnimations[index],
      builder: (context, child) {
        final scale = 0.8 + (0.2 * _stepAnimations[index].value);
        
        return Transform.scale(
          scale: scale,
          child: Column(
            children: [
              // Status icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getStepColor(status, isActive, isCurrent),
                  shape: BoxShape.circle,
                  border: isCurrent
                      ? Border.all(color: _getStepColor(status, isActive, isCurrent), width: 2)
                      : null,
                ),
                child: Icon(
                  _getStepIcon(status),
                  color: Colors.white,
                  size: 24,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Status label
              Text(
                _getStepLabel(status),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isActive ? Colors.black87 : Colors.grey[400],
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Builds progress bar
  Widget _buildProgressBar() {
    final currentStepIndex = _getStepIndex(widget.currentStatus);
    final totalSteps = _statusOrder.length;
    final progress = (currentStepIndex + 1) / totalSteps;
    
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
        width: MediaQuery.of(context).size.width * progress,
        decoration: BoxDecoration(
          color: _getProgressColor(),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  /// Gets step index for current status
  int _getStepIndex(EmergencyStatus status) {
    switch (status) {
      case EmergencyStatus.pending:
        return 0;
      case EmergencyStatus.accepted:
        return 1;
      case EmergencyStatus.inProgress:
        return 2;
      case EmergencyStatus.completed:
        return 3;
      case EmergencyStatus.cancelled:
      case EmergencyStatus.expired:
        return 0; // Treat as pending for display
    }
  }

  /// Gets icon for status step
  IconData _getStepIcon(EmergencyStatus status) {
    switch (status) {
      case EmergencyStatus.pending:
        return Icons.pending_actions;
      case EmergencyStatus.accepted:
        return Icons.check_circle;
      case EmergencyStatus.inProgress:
        return Icons.directions_car;
      case EmergencyStatus.completed:
        return Icons.task_alt;
      case EmergencyStatus.cancelled:
        return Icons.cancel;
      case EmergencyStatus.expired:
        return Icons.timer_off;
    }
  }

  /// Gets label for status step
  String _getStepLabel(EmergencyStatus status) {
    switch (status) {
      case EmergencyStatus.pending:
        return 'Request Sent';
      case EmergencyStatus.accepted:
        return 'Responder Assigned';
      case EmergencyStatus.inProgress:
        return 'En Route';
      case EmergencyStatus.completed:
        return 'Arrived';
      case EmergencyStatus.cancelled:
        return 'Cancelled';
      case EmergencyStatus.expired:
        return 'Expired';
    }
  }

  /// Gets color for status step
  Color _getStepColor(EmergencyStatus status, bool isActive, bool isCurrent) {
    if (!isActive) return Colors.grey[300]!;
    
    if (isCurrent) {
      return _getActiveStepColor(status);
    }
    
    return Colors.green;
  }

  /// Gets color for active step
  Color _getActiveStepColor(EmergencyStatus status) {
    switch (status) {
      case EmergencyStatus.pending:
        return Colors.orange;
      case EmergencyStatus.accepted:
        return Colors.blue;
      case EmergencyStatus.inProgress:
        return Colors.purple;
      case EmergencyStatus.completed:
        return Colors.green;
      case EmergencyStatus.cancelled:
        return Colors.red;
      case EmergencyStatus.expired:
        return Colors.grey;
    }
  }

  /// Gets progress bar color
  Color _getProgressColor() {
    switch (widget.currentStatus) {
      case EmergencyStatus.pending:
        return Colors.orange;
      case EmergencyStatus.accepted:
        return Colors.blue;
      case EmergencyStatus.inProgress:
        return Colors.purple;
      case EmergencyStatus.completed:
        return Colors.green;
      case EmergencyStatus.cancelled:
        return Colors.red;
      case EmergencyStatus.expired:
        return Colors.grey;
    }
  }
}
