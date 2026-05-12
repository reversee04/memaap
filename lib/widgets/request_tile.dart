import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/emergency_request_model.dart';
import '../services/location_service.dart';

/// Widget that displays emergency request information in a tile
/// 
/// Shows patient name, emergency type, distance, and elapsed time
/// with appropriate icons and colors for Mobile Emergency Medical Assistance App.
class RequestTile extends StatelessWidget {
  final EmergencyRequest request;
  final VoidCallback? onTap;

  const RequestTile({
    Key? key,
    required this.request,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Emergency type icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getEmergencyTypeColor(),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getEmergencyTypeIcon(),
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              
              // Request information
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Patient name and emergency type
                    Text(
                      'Patient: ${request.userId}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      request.typeDisplayName,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: _getEmergencyTypeColor(),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Description
                    if (request.description.isNotEmpty) ...[
                      Text(
                        request.description,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                    ],
                    
                    // Status and time
                    Row(
                      children: [
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStatusColor(),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            request.statusDisplayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        
                        // Time information
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              request.timeAgo,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                            if (request.estimatedArrivalMinutes != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'ETA: ${request.estimatedArrivalText}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Action arrow
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Gets the icon for emergency type
  IconData _getEmergencyTypeIcon() {
    switch (request.type) {
      case EmergencyType.medical:
        return Icons.medical_services;
      case EmergencyType.accident:
        return Icons.car_crash;
      case EmergencyType.cardiac:
        return Icons.favorite_border;
      case EmergencyType.stroke:
        return Icons.psychology;
      case EmergencyType.trauma:
        return Icons.healing;
      case EmergencyType.other:
        return Icons.help_outline;
    }
  }

  /// Gets the color for emergency type
  Color _getEmergencyTypeColor() {
    switch (request.type) {
      case EmergencyType.medical:
        return Colors.blue;
      case EmergencyType.accident:
        return Colors.red;
      case EmergencyType.cardiac:
        return Colors.pink;
      case EmergencyType.stroke:
        return Colors.purple;
      case EmergencyType.trauma:
        return Colors.orange;
      case EmergencyType.other:
        return Colors.grey;
    }
  }

  /// Gets the color for request status
  Color _getStatusColor() {
    switch (request.status) {
      case EmergencyStatus.pending:
        return Colors.orange;
      case EmergencyStatus.accepted:
        return Colors.blue;
      case EmergencyStatus.inProgress:
        return Colors.green;
      case EmergencyStatus.completed:
        return Colors.grey;
      case EmergencyStatus.cancelled:
        return Colors.red;
      case EmergencyStatus.expired:
        return Colors.grey;
    }
  }
}
