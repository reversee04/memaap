# Improvement Plan: Emergency Request Process

## Current State Analysis

### Existing Flow
1. User selects emergency type on dashboard
2. Confirms request via bottom sheet
3. App gets GPS location
4. Reverse geocodes coordinates to address
5. Creates request via API (or queues offline)
6. Falls back to SMS if API fails
7. Navigates to tracking screen

### Pain Points
- **No emergency severity levels**: All emergencies treated equally
- **Limited emergency type information**: Only type selection, no details
- **No medical history/context**: Responder doesn't know patient's condition
- **No quick emergency types**: Must go through full flow for common emergencies
- **No voice/video attachment**: Can't describe emergency visually
- **No emergency contacts**: No way to notify family/friends
- **No pre-filled information**: User must re-enter details each time
- **No emergency cancellation confirmation**: Easy to accidentally cancel
- **No emergency priority queue**: Critical emergencies not prioritized
- **No location accuracy indicator**: User doesn't know if GPS is accurate

---

## Proposed Improvements

### 1. Emergency Severity Classification
**Priority**: High
**Impact**: High

Add severity levels to prioritize critical emergencies:
- **Critical**: Life-threatening (heart attack, severe bleeding, unconscious)
- **Urgent**: Serious but not immediately life-threatening (broken bones, severe pain)
- **Non-Urgent**: Minor injuries or illnesses

**Benefits**:
- Responders can prioritize critical cases
- Better resource allocation
- Improved response times for critical cases

### 2. Enhanced Emergency Type Selection with Quick Actions
**Priority**: High
**Impact**: High

Add quick-access buttons for common emergencies:
- Heart Attack
- Stroke
- Severe Bleeding
- Difficulty Breathing
- Unconscious Person
- Choking
- Allergic Reaction
- Seizure

Each quick button pre-fills:
- Emergency type
- Severity level
- Common symptoms
- Recommended actions

**Benefits**:
- Faster emergency reporting
- Reduced cognitive load during emergencies
- Better information for responders

### 3. Medical History Integration
**Priority**: Medium
**Impact**: High

Allow users to:
- Store medical conditions (diabetes, hypertension, etc.)
- Store allergies
- Store current medications
- Store blood type
- Store emergency contacts

Display this information to responders when they accept the request.

**Benefits**:
- Responders have critical medical context
- Better treatment decisions
- Reduced risk of allergic reactions or medication conflicts

### 4. Voice/Photo/Video Attachments
**Priority**: Medium
**Impact**: Medium

Allow users to:
- Record voice message describing emergency
- Take photos of injury/scene
- Record short video of situation

**Benefits**:
- Better situational awareness for responders
- Visual context helps responders prepare
- Voice attachment helps when typing is difficult

### 5. Emergency Contact Notifications
**Priority**: Medium
**Impact**: High

Automatically notify emergency contacts when request is created:
- Send SMS with emergency details
- Include location link
- Include responder information when assigned

**Benefits**:
- Family/friends are informed
- They can provide additional information
- They can meet at hospital

### 6. User Profile with Pre-filled Information
**Priority**: Low
**Impact**: Medium

Store user profile with:
- Name, age, gender
- Blood type
- Medical conditions
- Allergies
- Current medications
- Emergency contacts
- Preferred hospital

Pre-fill this information in emergency requests.

**Benefits**:
- Faster emergency reporting
- More accurate information
- Better responder preparation

### 7. Location Accuracy Indicator
**Priority**: Low
**Impact**: Medium

Show GPS accuracy to user:
- High accuracy (<10m): Green indicator
- Medium accuracy (10-50m): Yellow indicator
- Low accuracy (>50m): Red indicator with option to retry

**Benefits**:
- User knows if location is reliable
- Can retry if accuracy is poor
- Responders know location reliability

### 8. Emergency Cancellation Confirmation
**Priority**: Low
**Impact**: Low

Add confirmation dialog when cancelling:
- Show reason selection (mistake, resolved, other)
- Require confirmation
- Log cancellation reason

**Benefits**:
- Prevent accidental cancellations
- Better data for analysis
- Can follow up if needed

### 9. Emergency Priority Queue
**Priority**: High
**Impact**: High

Implement priority queue for responders:
- Critical emergencies shown first
- Urgent emergencies shown second
- Non-urgent emergencies shown last
- Time-based escalation (urgent becomes critical after 5 minutes)

**Benefits**:
- Critical cases get faster response
- Better resource allocation
- Improved patient outcomes

### 10. Offline Mode Improvements
**Priority**: Medium
**Impact**: Medium

Enhance offline emergency handling:
- Show clear offline indicator
- Queue requests with priority
- Auto-sync when online
- Show sync status
- Allow manual sync trigger

**Benefits**:
- Better user experience offline
- No lost requests
- Clear communication of status

---

## Implementation Plan

### Phase 1: Critical Improvements (Week 1-2)

#### 1.1 Emergency Severity Classification
**Files to modify**:
- `lib/models/emergency_request_model.dart` - Add EmergencySeverity enum
- `lib/screens/confirm_request_screen.dart` - Add severity selector
- `lib/services/emergency_service.dart` - Include severity in request
- `backend/src/repositories/emergency-request.repository.ts` - Store severity
- `backend/src/routes/emergency.routes.ts` - Accept severity in API

**Steps**:
1. Add EmergencySeverity enum (critical, urgent, non_urgent)
2. Add severity field to EmergencyRequest model
3. Add severity selector UI with color coding
4. Update API to handle severity
5. Update database schema
6. Test severity-based sorting

**Estimated time**: 8 hours

#### 1.2 Quick Emergency Type Buttons
**Files to modify**:
- `lib/screens/confirm_request_screen.dart` - Add quick buttons
- `lib/models/emergency_request_model.dart` - Add predefined types
- `lib/services/emergency_service.dart` - Handle quick types

**Steps**:
1. Create predefined emergency types with metadata
2. Add quick button grid to confirmation screen
3. Pre-fill information based on selection
4. Keep custom type option
5. Test all quick types

**Estimated time**: 6 hours

#### 1.3 Emergency Priority Queue
**Files to modify**:
- `lib/screens/responder_dashboard.dart` - Implement priority sorting
- `lib/repositories/emergency_repository.dart` - Add priority query
- `backend/src/repositories/emergency-request.repository.ts` - Add priority query

**Steps**:
1. Add priority sorting logic (severity + time)
2. Update dashboard to show priority indicators
3. Implement time-based escalation
4. Test priority queue with mixed requests
5. Add priority badges to UI

**Estimated time**: 10 hours

### Phase 2: Medium Priority Improvements (Week 3-4)

#### 2.1 Medical History Integration
**Files to modify**:
- `lib/models/user_model.dart` - Add medical fields
- `lib/screens/profile_screen.dart` - Add medical info UI
- `lib/screens/responder_dashboard.dart` - Show medical info
- `backend/src/repositories/user.repository.ts` - Store medical info

**Steps**:
1. Add medical fields to user model
2. Create medical profile screen
3. Update emergency request to include medical info
4. Display medical info to responders
5. Test with various medical conditions

**Estimated time**: 12 hours

#### 2.2 Emergency Contact Notifications
**Files to modify**:
- `lib/models/user_model.dart` - Add emergency contacts
- `lib/screens/profile_screen.dart` - Add contact management
- `lib/services/emergency_service.dart` - Send notifications
- `backend/src/services/notification.service.ts` - SMS service

**Steps**:
1. Add emergency contacts to user model
2. Create contact management UI
3. Implement SMS notification service
4. Send notifications on request creation
5. Send notifications on responder assignment
6. Test notification delivery

**Estimated time**: 10 hours

#### 2.3 Voice/Photo/Video Attachments
**Files to modify**:
- `lib/models/emergency_request_model.dart` - Add attachment fields
- `lib/screens/confirm_request_screen.dart` - Add attachment UI
- `lib/services/emergency_service.dart` - Handle attachments
- `backend/src/routes/emergency.routes.ts` - Accept attachments
- Storage service for media files

**Steps**:
1. Add attachment fields to model
2. Implement photo capture
3. Implement voice recording
4. Implement video recording
5. Upload attachments to storage
6. Display attachments to responders
7. Test all attachment types

**Estimated time**: 16 hours

#### 2.4 Offline Mode Improvements
**Files to modify**:
- `lib/repositories/emergency_repository.dart` - Enhance offline queue
- `lib/services/emergency_service.dart` - Show offline status
- `lib/screens/confirm_request_screen.dart` - Offline indicator

**Steps**:
1. Add offline indicator to UI
2. Show queue status
3. Implement priority-based offline queue
4. Add manual sync trigger
5. Show sync progress
6. Test offline scenarios

**Estimated time**: 8 hours

### Phase 3: Low Priority Improvements (Week 5)

#### 3.1 User Profile with Pre-filled Information
**Files to modify**:
- `lib/screens/profile_screen.dart` - Add profile fields
- `lib/models/user_model.dart` - Add profile fields
- `lib/screens/confirm_request_screen.dart` - Pre-fill from profile

**Steps**:
1. Add profile fields (name, age, blood type, etc.)
2. Create profile management UI
3. Pre-fill emergency form from profile
4. Test profile creation and usage

**Estimated time**: 6 hours

#### 3.2 Location Accuracy Indicator
**Files to modify**:
- `lib/services/location_service.dart` - Return accuracy
- `lib/screens/confirm_request_screen.dart` - Show accuracy
- `lib/services/emergency_service.dart` - Handle accuracy

**Steps**:
1. Get GPS accuracy from location service
2. Add accuracy indicator UI
3. Color-code based on accuracy
4. Add retry option for poor accuracy
5. Test with various GPS conditions

**Estimated time**: 4 hours

#### 3.3 Emergency Cancellation Confirmation
**Files to modify**:
- `lib/screens/tracking_screen.dart` - Add confirmation dialog
- `lib/repositories/emergency_repository.dart` - Log cancellation reason

**Steps**:
1. Add cancellation dialog with reason selection
2. Log cancellation reason
3. Require confirmation
4. Test cancellation flow

**Estimated time**: 3 hours

---

## Testing Plan

### Unit Tests
- EmergencySeverity enum parsing
- Priority queue sorting logic
- Medical history serialization
- Attachment upload/download
- Offline queue management

### Integration Tests
- End-to-end emergency request with severity
- Quick type button functionality
- Medical info display to responders
- Emergency contact notification delivery
- Attachment upload and display

### Manual Testing Scenarios
1. Create critical emergency - verify priority
2. Create urgent emergency - verify queue position
3. Create non-urgent emergency - verify queue position
4. Test time-based escalation
5. Test quick type buttons
6. Test medical history display
7. Test emergency contact notifications
8. Test voice/photo/video attachments
9. Test offline mode with queue
10. Test location accuracy indicator
11. Test cancellation confirmation

---

## Estimated Timeline

- **Phase 1**: 2 weeks (24 hours)
- **Phase 2**: 2 weeks (46 hours)
- **Phase 3**: 1 week (13 hours)
- **Testing**: 1 week (20 hours)
- **Total**: 6 weeks (103 hours)

---

## Risks and Mitigations

### Risk 1: Users may not understand severity levels
**Mitigation**: Add clear descriptions and examples for each level, use color coding

### Risk 2: Medical information privacy concerns
**Mitigation**: Add privacy policy, allow users to opt-in, encrypt sensitive data

### Risk 3: Attachment storage costs
**Mitigation**: Limit attachment size, auto-delete after 30 days, use compression

### Risk 4: SMS notification costs
**Mitigation**: Use bulk SMS provider, limit to 2 contacts per emergency, add usage limits

### Risk 5: Priority queue complexity
**Mitigation**: Start with simple severity-based sorting, add time-based escalation later

### Risk 6: Offline sync conflicts
**Mitigation**: Use timestamp-based conflict resolution, manual conflict resolution UI

---

## Success Metrics

- **Reduced emergency reporting time**: From 60s to 30s average
- **Improved critical response time**: From 10min to 5min average
- **Increased medical information availability**: From 0% to 80% of requests
- **Reduced accidental cancellations**: From 5% to <1%
- **Improved location accuracy**: From 50m to 20m average
- **Increased offline request success**: From 70% to 95%
