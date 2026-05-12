/// Enum for notification types
enum NotificationType {
  emergencyUpdate,
  chat,
  system,
  responderUpdate,
  hospitalUpdate,
}

/// Enum for notification priority
enum NotificationPriority {
  low,
  normal,
  high,
  urgent,
}

/// Model class for push notification data
/// 
/// Represents a notification in the Mobile Emergency Medical Assistance App
/// with type, content, and action handling.
class NotificationModel {
  final String id;
  final String userId;
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final NotificationPriority priority;
  final DateTime createdAt;
  final bool isRead;
  final String? imageUrl;
  final String? actionUrl;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.data,
    required this.priority,
    required this.createdAt,
    this.isRead = false,
    this.imageUrl,
    this.actionUrl,
  });

  /// Creates a copy of this model with updated values
  NotificationModel copyWith({
    String? id,
    String? userId,
    NotificationType? type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    NotificationPriority? priority,
    DateTime? createdAt,
    bool? isRead,
    String? imageUrl,
    String? actionUrl,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      imageUrl: imageUrl ?? this.imageUrl,
      actionUrl: actionUrl ?? this.actionUrl,
    );
  }

  /// Creates a NotificationModel from a JSON map
  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? json['user_id']?.toString() ?? '',
      type: _parseNotificationType(json['type'] ?? json['notification_type']),
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      data: json['data'] as Map<String, dynamic>?,
      priority: _parseNotificationPriority(json['priority'] ?? json['notification_priority']),
      createdAt: DateTime.tryParse(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      isRead: json['isRead'] ?? json['is_read'] ?? false,
      imageUrl: json['imageUrl'] ?? json['image_url'],
      actionUrl: json['actionUrl'] ?? json['action_url'],
    );
  }

  /// Converts the model to a JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'type': type.name,
      'title': title,
      'body': body,
      if (data != null) 'data': data,
      'priority': priority.name,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (actionUrl != null) 'actionUrl': actionUrl,
    };
  }

  /// Converts the model to a database map for SQLite storage
  Map<String, dynamic> toDatabaseMap() {
    return {
      'id': id,
      'user_id': userId,
      'notification_type': type.name,
      'title': title,
      'body': body,
      'data': data != null ? jsonEncode(data) : null,
      'notification_priority': priority.name,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead ? 1 : 0,
      'image_url': imageUrl,
      'action_url': actionUrl,
    };
  }

  /// Creates a NotificationModel from database map
  factory NotificationModel.fromDatabaseMap(Map<String, dynamic> map) {
    Map<String, dynamic>? data;
    if (map['data'] != null) {
      try {
        data = jsonDecode(map['data'] as String);
      } catch (e) {
        // Keep data null if parsing fails
      }
    }

    return NotificationModel(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      type: _parseNotificationType(map['notification_type'] ?? ''),
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      data: data,
      priority: _parseNotificationPriority(map['notification_priority'] ?? ''),
      createdAt: DateTime.tryParse(map['created_at']) ?? DateTime.now(),
      isRead: (map['is_read'] ?? 0) == 1,
      imageUrl: map['image_url'],
      actionUrl: map['action_url'],
    );
  }

  /// Parses notification type from string
  static NotificationType _parseNotificationType(String typeString) {
    switch (typeString.toLowerCase()) {
      case 'emergency_update':
        return NotificationType.emergencyUpdate;
      case 'chat':
        return NotificationType.chat;
      case 'system':
        return NotificationType.system;
      case 'responder_update':
        return NotificationType.responderUpdate;
      case 'hospital_update':
        return NotificationType.hospitalUpdate;
      default:
        return NotificationType.system;
    }
  }

  /// Parses notification priority from string
  static NotificationPriority _parseNotificationPriority(String priorityString) {
    switch (priorityString.toLowerCase()) {
      case 'low':
        return NotificationPriority.low;
      case 'normal':
        return NotificationPriority.normal;
      case 'high':
        return NotificationPriority.high;
      case 'urgent':
        return NotificationPriority.urgent;
      default:
        return NotificationPriority.normal;
    }
  }

  /// Gets the display name for notification type
  String get typeDisplayName {
    switch (type) {
      case NotificationType.emergencyUpdate:
        return 'Emergency Update';
      case NotificationType.chat:
        return 'Chat Message';
      case NotificationType.system:
        return 'System';
      case NotificationType.responderUpdate:
        return 'Responder Update';
      case NotificationType.hospitalUpdate:
        return 'Hospital Update';
    }
  }

  /// Gets the display name for notification priority
  String get priorityDisplayName {
    switch (priority) {
      case NotificationPriority.low:
        return 'Low';
      case NotificationPriority.normal:
        return 'Normal';
      case NotificationPriority.high:
        return 'High';
      case NotificationPriority.urgent:
        return 'Urgent';
    }
  }

  /// Checks if the notification is high priority or urgent
  bool get isHighPriority {
    return priority == NotificationPriority.high || priority == NotificationPriority.urgent;
  }

  /// Gets the time since creation as a formatted string
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  @override
  String toString() {
    return 'NotificationModel(id: $id, type: $typeDisplayName, title: $title)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NotificationModel &&
        other.id == id &&
        other.userId == userId &&
        other.type == type;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        userId.hashCode ^
        type.hashCode;
  }
}
