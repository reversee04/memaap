# Implementation Plan: Emergency Requester Call Responder Feature

## Overview
Allow patients (emergency requesters) to directly call the emergency responder who has accepted their emergency request via the tracking screen.

## Current State
- Emergency requests are created by patients
- Responders can accept requests via the responder dashboard
- Tracking screen shows request status and responder location
- No direct communication channel between patient and responder

## Target State
- Patient can call the assigned responder directly from the tracking screen
- Responder's phone number is displayed and accessible
- Call button is only visible when a responder is assigned
- Proper permissions are handled for phone calls

---

## Backend Changes

### 1. Update Emergency Request Model
**File**: `backend/src/repositories/emergency-request.repository.ts`

- Add `responder_phone` column to emergency_requests table (if not already present)
- Update `create` method to optionally include responder phone when assigning
- Update `assignResponder` method to include responder's phone number

```sql
ALTER TABLE emergency_requests ADD COLUMN responder_phone TEXT;
```

### 2. Update User Model
**File**: `backend/src/repositories/user.repository.ts` (if exists)

- Ensure responder users have a `phone` field in their profile
- Add validation for phone number format

### 3. Update Emergency Routes
**File**: `backend/src/routes/emergency.routes.ts`

- Modify `PUT /api/emergency/:id/accept` endpoint to include responder's phone in response
- Add `GET /api/emergency/:id/responder-info` endpoint to get responder contact details

```typescript
// Update accept endpoint to include responder phone
router.put('/:id/accept', requireAuth, (req: Request, res: Response) => {
  try {
    const { userId, role } = res.locals.user;
    
    if (role !== 'responder' && role !== 'admin') {
      return res.status(403).json({ message: 'Only responders can accept requests' });
    }

    const emergency = EmergencyRequestRepository.assignResponder(req.params.id, userId);
    if (!emergency) return res.status(404).json({ message: 'Emergency not found or already accepted' });

    // Fetch responder phone number
    const responder = UserRepository.findById(userId);
    const emergencyWithPhone = {
      ...emergency,
      responder_phone: responder?.phone || null
    };

    return res.json({ emergency: emergencyWithPhone });
  } catch (err: any) {
    console.error('Accept emergency error:', err);
    return res.status(500).json({ message: 'Failed to accept emergency request' });
  }
});
```

### 4. Update Database Schema
**File**: `backend/src/config/database.ts`

- Add migration to add `responder_phone` column to emergency_requests table
- Ensure the column is added on database initialization

---

## Frontend Changes

### 1. Update Emergency Request Model
**File**: `lib/models/emergency_request_model.dart`

- Add `responderPhone` field to the EmergencyRequest class
- Update `fromJson` and `toDatabaseMap` methods to handle responder phone
- Add `toDatabaseMap` to include responder_phone

```dart
class EmergencyRequest {
  final String id;
  final String userId;
  final EmergencyType type;
  final String? description;
  final double latitude;
  final double longitude;
  final String? address;
  final EmergencyStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? responderId;  // Add if not present
  final String? responderPhone;  // NEW FIELD
  final bool isOfflineQueued;

  // Constructor with new field
  EmergencyRequest({
    required this.id,
    required this.userId,
    required this.type,
    this.description,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.responderId,
    this.responderPhone,  // NEW
    this.isOfflineQueued = false,
  });

  // Update fromJson
  factory EmergencyRequest.fromJson(Map<String, dynamic> json) {
    return EmergencyRequest(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? json['userId'] ?? '',
      type: _parseEmergencyType(json['type']),
      description: json['description'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'],
      status: _parseEmergencyStatus(json['status']),
      createdAt: DateTime.parse(json['created_at'] ?? json['createdAt']),
      updatedAt: DateTime.parse(json['updated_at'] ?? json['updatedAt']),
      responderId: json['responder_id'] ?? json['responderId'],
      responderPhone: json['responder_phone'] ?? json['responderPhone'],  // NEW
      isOfflineQueued: json['is_offline_queued'] ?? json['isOfflineQueued'] ?? false,
    );
  }

  // Update toDatabaseMap
  Map<String, dynamic> toDatabaseMap() {
    return {
      'id': id,
      'user_id': userId,
      'type': type.toString().split('.').last,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'status': status.toString().split('.').last,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'responder_id': responderId,
      'responder_phone': responderPhone,  // NEW
      'is_offline_queued': isOfflineQueued ? 1 : 0,
    };
  }

  // Add copyWith method if not present
  EmergencyRequest copyWith({
    String? id,
    String? userId,
    EmergencyType? type,
    String? description,
    double? latitude,
    double? longitude,
    String? address,
    EmergencyStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? responderId,
    String? responderPhone,
    bool? isOfflineQueued,
  }) {
    return EmergencyRequest(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      responderId: responderId ?? this.responderId,
      responderPhone: responderPhone ?? this.responderPhone,
      isOfflineQueued: isOfflineQueued ?? this.isOfflineQueued,
    );
  }
}
```

### 2. Update Emergency Repository
**File**: `lib/repositories/emergency_repository.dart`

- Ensure `getAllRequests` and `getRequestById` methods include responder_phone in the query
- Update `_storeRequestLocally` to save responder_phone to local database

```dart
static Future<void> _storeRequestLocally(EmergencyRequest request) async {
  final db = await DatabaseHelper().database;
  await db.insert(
    DatabaseHelper.tableEmergencyRequests,
    request.toDatabaseMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
```

### 3. Add Phone Call Service
**File**: `lib/services/phone_call_service.dart` (NEW FILE)

Create a new service to handle phone calls with proper error handling and permissions.

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service for handling phone calls to emergency responders
class PhoneCallService {
  /// Initiates a phone call to the specified phone number
  /// 
  /// [phoneNumber] - The phone number to call (with or without country code)
  /// [context] - BuildContext for showing dialogs
  /// 
  /// Returns true if the call was initiated successfully
  static Future<bool> makePhoneCall({
    required String phoneNumber,
    required BuildContext context,
  }) async {
    try {
      // Clean the phone number
      final cleanNumber = _cleanPhoneNumber(phoneNumber);
      
      if (cleanNumber.isEmpty) {
        _showErrorDialog(context, 'Invalid phone number');
        return false;
      }

      // Check and request phone call permission
      final permissionStatus = await _requestPhonePermission(context);
      if (!permissionStatus) {
        return false;
      }

      // Create the phone URI
      final phoneUri = Uri(scheme: 'tel', path: cleanNumber);
      
      // Check if phone call is available
      if (!await launchUrl(phoneUri)) {
        _showErrorDialog(context, 'Could not launch phone call');
        return false;
      }

      return true;
    } catch (e) {
      _showErrorDialog(context, 'Error making phone call: $e');
      return false;
    }
  }

  /// Cleans the phone number by removing non-digit characters
  static String _cleanPhoneNumber(String phoneNumber) {
    return phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
  }

  /// Requests phone call permission from the user
  static Future<bool> _requestPhonePermission(BuildContext context) async {
    final status = await Permission.phone.status;
    
    if (status.isGranted) {
      return true;
    }

    if (status.isDenied) {
      final result = await Permission.phone.request();
      return result.isGranted;
    }

    if (status.isPermanentlyDenied) {
      _showPermissionDeniedDialog(context);
      return false;
    }

    return false;
  }

  /// Shows a dialog when permission is permanently denied
  static void _showPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Phone call permission is required to call the emergency responder. '
          'Please enable it in app settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.of(context).pop();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Shows an error dialog
  static void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
```

### 4. Update Tracking Screen UI
**File**: `lib/screens/tracking_screen.dart`

- Add a call button in the app bar or main UI when responder is assigned
- Show responder's phone number
- Handle call button press using PhoneCallService

```dart
// In _TrackingScreenState class, add method to handle call
void _callResponder() async {
  if (_currentRequest?.responderPhone == null || 
      _currentRequest!.responderPhone!.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Responder phone number not available')),
    );
    return;
  }

  final success = await PhoneCallService.makePhoneCall(
    phoneNumber: _currentRequest!.responderPhone!,
    context: context,
  );

  if (!success) {
    debugPrint('Failed to initiate phone call');
  }
}

// In build method, update app bar actions
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('Emergency Tracking'),
      backgroundColor: Colors.red,
      foregroundColor: Colors.white,
      actions: [
        // Call button - only show when responder is assigned
        if (_currentRequest?.responderPhone != null && 
            _currentRequest!.responderPhone!.isNotEmpty)
          IconButton(
            onPressed: _callResponder,
            icon: const Icon(Icons.phone),
            tooltip: 'Call Responder',
          ),
        if (_currentRequest?.status == EmergencyStatus.pending)
          IconButton(
            onPressed: _cancelRequest,
            icon: const Icon(Icons.cancel),
            tooltip: 'Cancel Request',
          ),
      ],
    ),
    // ... rest of the UI
  );
}
```

### 5. Add Responder Info Card (Optional Enhancement)
**File**: `lib/screens/tracking_screen.dart`

Add a card showing responder information when assigned.

```dart
// Add this widget to show responder info
Widget _buildResponderInfoCard() {
  if (_currentRequest?.responderPhone == null || 
      _currentRequest!.responderPhone!.isEmpty) {
    return const SizedBox.shrink();
  }

  return Card(
    margin: const EdgeInsets.all(16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                'Responder Assigned',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.phone, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                _currentRequest!.responderPhone!,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _callResponder,
              icon: const Icon(Icons.phone),
              label: const Text('Call Responder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
```

### 6. Update Android Permissions
**File**: `android/app/src/main/AndroidManifest.xml`

Add phone call permission:

```xml
<uses-permission android:name="android.permission.CALL_PHONE" />
```

### 7. Update iOS Permissions
**File**: `ios/Runner/Info.plist`

Add phone call permission if needed (iOS typically doesn't require explicit permission for dialing):

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>tel</string>
</array>
```

### 8. Add Dependencies
**File**: `pubspec.yaml`

Add required dependencies if not already present:

```yaml
dependencies:
  url_launcher: ^6.1.11
  permission_handler: ^11.0.1
```

---

## Testing Plan

### 1. Unit Tests
- Test PhoneCallService with various phone number formats
- Test permission handling scenarios
- Test EmergencyRequest model serialization with responder_phone

### 2. Integration Tests
- Test backend API returns responder_phone when accepting request
- Test local database stores and retrieves responder_phone
- Test tracking screen displays call button correctly

### 3. Manual Testing
1. **Scenario 1: No responder assigned**
   - Create emergency request
   - Verify call button is NOT visible
   - Verify no phone number is shown

2. **Scenario 2: Responder assigned with phone**
   - Create emergency request
   - Responder accepts request
   - Verify call button IS visible
   - Verify phone number is displayed
   - Tap call button
   - Verify phone dialer opens with correct number
   - Verify call can be made

3. **Scenario 3: Permission denied**
   - Deny phone permission
   - Tap call button
   - Verify permission dialog is shown
   - Grant permission
   - Verify call works

4. **Scenario 4: Invalid phone number**
   - Test with empty phone number
   - Test with malformed phone number
   - Verify appropriate error messages

5. **Scenario 5: Offline mode**
   - Create request offline
   - Responder accepts when online
   - Verify phone number syncs correctly

---

## Implementation Order

1. **Backend Changes** (Priority: High)
   - Update database schema
   - Update repository methods
   - Update API routes
   - Test backend endpoints

2. **Frontend Model Updates** (Priority: High)
   - Update EmergencyRequest model
   - Update emergency repository
   - Test data serialization

3. **Phone Call Service** (Priority: High)
   - Create PhoneCallService
   - Add dependencies
   - Test permission handling

4. **UI Updates** (Priority: Medium)
   - Update tracking screen
   - Add call button
   - Add responder info card (optional)

5. **Permissions** (Priority: Medium)
   - Update AndroidManifest.xml
   - Update Info.plist
   - Test on both platforms

6. **Testing** (Priority: High)
   - Unit tests
   - Integration tests
   - Manual testing scenarios

---

## Estimated Time

- Backend changes: 2-3 hours
- Frontend model updates: 1-2 hours
- Phone call service: 2-3 hours
- UI updates: 2-3 hours
- Testing: 3-4 hours
- **Total: 10-15 hours**

---

## Risks and Mitigations

### Risk 1: Responder phone number not available
**Mitigation**: Handle gracefully - show "Contact not available" message, hide call button

### Risk 2: Permission denied on iOS/Android
**Mitigation**: Provide clear instructions to enable permissions in settings, show helpful dialogs

### Risk 3: Phone number format issues
**Mitigation**: Clean phone numbers before use, support multiple formats, validate input

### Risk 4: Backend API changes break existing functionality
**Mitigation**: Make responder_phone optional, ensure backward compatibility, thorough testing

### Risk 5: User privacy concerns
**Mitigation**: Only show phone number to the patient who made the request, add privacy policy if needed

---

## Future Enhancements

1. **Video Call Integration**: Add option for video calls using WebRTC
2. **In-App Messaging**: Add chat functionality between patient and responder
3. **Call History**: Track call attempts and duration
4. **Emergency SOS**: Add quick SOS button that calls responder and emergency services
5. **VoIP Integration**: Use VoIP for cheaper calls over data connection
