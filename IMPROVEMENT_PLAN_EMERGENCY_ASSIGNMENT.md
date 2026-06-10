# Improvement Plan: Emergency Assignment Process

## Current State Analysis

### Existing Flow
1. Emergency request created with status "pending"
2. All responders see pending requests on dashboard
3. Responders manually browse and accept requests
4. First responder to accept gets assigned
6. Request status changes to "accepted"
7. No automatic assignment or prioritization

### Pain Points
- **No automatic assignment**: Relies on manual responder action
- **No proximity-based assignment**: Closest responder not prioritized
- **No skill-based assignment**: No consideration of responder specialization
- **No workload balancing**: Some responders may be overwhelmed
- **No ETA estimation**: Patient doesn't know when help will arrive
- **No responder availability status**: Can't tell if responder is busy
- **No reassignment capability**: If responder can't respond, no fallback
- **No assignment history**: Can't track assignment patterns
- **No multi-responder support**: Can't assign multiple responders for critical cases
- **No assignment timeout**: Request can sit unassigned indefinitely

---

## Proposed Improvements

### 1. Automatic Proximity-Based Assignment
**Priority**: High
**Impact**: High

Automatically assign requests to the closest available responder:
- Calculate distance between patient and all available responders
- Sort responders by distance
- Auto-assign to closest responder
- Allow responder to decline with reason
- If declined, assign to next closest

**Benefits**:
- Faster response times
- Reduced manual effort
- Better resource utilization
- Improved patient outcomes

### 2. Responder Availability Status
**Priority**: High
**Impact**: High

Track responder availability:
- **Available**: Ready to accept requests
- **Busy**: Currently handling an emergency
- **Offline**: Not logged in
- **On Break**: Temporarily unavailable
- **In Transit**: En route to emergency

**Benefits**:
- Only available responders get assignments
- Better workload management
- Clear status communication
- Prevents over-assignment

### 3. Skill-Based Assignment
**Priority**: Medium
**Impact**: High

Match responders based on skills and emergency type:
- Medical emergencies → Medical responders
- Fire emergencies → Fire responders
- Rescue emergencies → Rescue responders
- General emergencies → Any available responder

Responder profiles include:
- Certifications (EMT, Paramedic, First Aid)
- Specializations (Trauma, Cardiac, Pediatric)
- Experience level
- Languages spoken

**Benefits**:
- Better match between emergency and responder
- Improved patient outcomes
- More efficient resource use
- Professional satisfaction

### 4. Workload Balancing
**Priority**: Medium
**Impact**: Medium

Distribute requests evenly among responders:
- Track current assignments per responder
- Assign to responder with fewest active assignments
- Consider assignment history
- Prevent burnout by limiting concurrent assignments

**Benefits**:
- Fair workload distribution
- Prevents responder burnout
- Better overall response capacity
- Improved responder satisfaction

### 5. ETA Estimation
**Priority**: High
**Impact**: High

Calculate and display estimated arrival time:
- Calculate distance between responder and patient
- Use average speed based on road type
- Consider traffic conditions (if available)
- Update ETA in real-time as responder moves
- Show ETA to patient on tracking screen

**Benefits**:
- Patient knows when to expect help
- Reduces anxiety
- Better communication
- Transparency in service

### 6. Assignment Timeout and Escalation
**Priority**: High
**Impact**: High

Implement timeout mechanism:
- If no responder accepts within X minutes, escalate
- Escalation options:
  - Expand search radius
  - Notify all responders (not just nearby)
  - Alert supervisor/admin
  - Send SMS to backup responders
- Critical emergencies have shorter timeout

**Benefits**:
- No request sits unassigned
- Faster escalation for critical cases
- Better patient safety
- Accountability

### 7. Reassignment Capability
**Priority**: Medium
**Impact**: Medium

Allow reassignment when needed:
- Responder can decline assignment with reason
- Admin can manually reassign
- Auto-reassign if responder doesn't respond within Y minutes
- Reassign if responder is delayed
- Keep assignment history

**Benefits**:
- Flexibility in assignments
- Better handling of delays
- Improved reliability
- Accountability tracking

### 8. Multi-Responder Assignment
**Priority**: Medium
**Impact**: High

Assign multiple responders for critical emergencies:
- Critical emergencies can have 2-3 responders
- Primary responder + backup
- Different specializations for complex cases
- Coordination between responders
- Patient sees all assigned responders

**Benefits**:
- Better response for critical cases
- Redundancy for reliability
- Specialized care
- Improved patient outcomes

### 9. Assignment History and Analytics
**Priority**: Low
**Impact**: Medium

Track assignment patterns:
- Response times per responder
- Assignment success rate
- Decline reasons
- Geographic patterns
- Time-of-day patterns
- Skill utilization

**Benefits**:
- Data-driven improvements
- Identify training needs
- Optimize responder placement
- Performance tracking

### 10. Responder Preferences and Constraints
**Priority**: Low
**Impact**: Medium

Allow responders to set preferences:
- Preferred geographic area
- Maximum travel distance
- Preferred emergency types
- Available hours
- Language preferences

**Benefits**:
- Better responder satisfaction
- More efficient assignments
- Reduced declines
- Better work-life balance

---

## Implementation Plan

### Phase 1: Critical Improvements (Week 1-2)

#### 1.1 Responder Availability Status
**Files to modify**:
- `lib/models/user_model.dart` - Add availability status
- `lib/screens/responder_dashboard.dart` - Show status selector
- `backend/src/repositories/user.repository.ts` - Store availability
- `backend/src/routes/emergency.routes.ts` - Update assignment logic

**Steps**:
1. Add ResponderAvailability enum (available, busy, offline, on_break, in_transit)
2. Add availability field to user model
3. Create status selector UI
4. Update assignment logic to filter by availability
5. Auto-update status when accepting/completing requests
6. Test status transitions

**Estimated time**: 10 hours

#### 1.2 Automatic Proximity-Based Assignment
**Files to modify**:
- `backend/src/repositories/emergency-request.repository.ts` - Add proximity assignment
- `backend/src/services/assignment.service.ts` (NEW) - Assignment logic
- `backend/src/routes/emergency.routes.ts` - Use assignment service
- `lib/repositories/emergency_repository.dart` - Handle auto-assignment

**Steps**:
1. Create assignment service with proximity calculation
2. Get all available responders
3. Calculate distances to patient location
4. Sort by distance
5. Auto-assign to closest responder
6. Add decline capability
7. Test with multiple responders

**Estimated time**: 14 hours

#### 1.3 ETA Estimation
**Files to modify**:
- `backend/src/services/eta.service.ts` (NEW) - ETA calculation
- `lib/models/emergency_request_model.dart` - Add ETA field
- `lib/screens/tracking_screen.dart` - Display ETA
- `lib/screens/responder_dashboard.dart` - Show ETA for requests

**Steps**:
1. Create ETA service with distance calculation
2. Use Google Maps Distance Matrix API for accurate ETA
3. Calculate ETA when responder is assigned
4. Update ETA in real-time as responder moves
5. Display ETA to patient
6. Test with various distances

**Estimated time**: 12 hours

#### 1.4 Assignment Timeout and Escalation
**Files to modify**:
- `backend/src/services/assignment.service.ts` - Add timeout logic
- `backend/src/services/notification.service.ts` - Send escalation alerts
- `lib/repositories/emergency_repository.dart` - Handle timeout

**Steps**:
1. Add timeout configuration (critical: 2min, urgent: 5min, non-urgent: 10min)
2. Implement timeout check (cron job or scheduled task)
3. Add escalation logic (expand radius, notify all, alert admin)
4. Send escalation notifications
5. Test timeout scenarios

**Estimated time**: 10 hours

### Phase 2: Medium Priority Improvements (Week 3-4)

#### 2.1 Skill-Based Assignment
**Files to modify**:
- `lib/models/user_model.dart` - Add skills/certifications
- `lib/screens/profile_screen.dart` - Add skill management UI
- `backend/src/repositories/user.repository.ts` - Store skills
- `backend/src/services/assignment.service.ts` - Match by skills
- `lib/models/emergency_request_model.dart` - Add required skills

**Steps**:
1. Add skills/certifications to user model
2. Create skill management UI
3. Add skill requirements to emergency types
4. Update assignment logic to match skills
5. Test skill-based matching

**Estimated time**: 12 hours

#### 2.2 Workload Balancing
**Files to modify**:
- `backend/src/services/assignment.service.ts` - Add workload tracking
- `backend/src/repositories/emergency-request.repository.ts` - Query active assignments
- `lib/screens/responder_dashboard.dart` - Show workload

**Steps**:
1. Track active assignments per responder
2. Add workload score to assignment algorithm
3. Limit concurrent assignments (max 2-3)
4. Show workload to admins
5. Test with multiple concurrent requests

**Estimated time**: 8 hours

#### 2.3 Reassignment Capability
**Files to modify**:
- `backend/src/routes/emergency.routes.ts` - Add reassignment endpoint
- `lib/screens/responder_dashboard.dart` - Add decline button
- `lib/screens/admin_dashboard.dart` - Add reassignment UI
- `backend/src/services/assignment.service.ts` - Handle reassignment

**Steps**:
1. Add decline endpoint with reason
2. Add admin reassignment endpoint
3. Create decline UI with reason selection
4. Create admin reassignment UI
5. Implement auto-reassignment on timeout
6. Test reassignment scenarios

**Estimated time**: 10 hours

#### 2.4 Multi-Responder Assignment
**Files to modify**:
- `lib/models/emergency_request_model.dart` - Support multiple responders
- `backend/src/repositories/emergency-request.repository.ts` - Store multiple responders
- `backend/src/services/assignment.service.ts` - Assign multiple responders
- `lib/screens/tracking_screen.dart` - Show all responders
- `lib/screens/responder_dashboard.dart` - Show co-responders

**Steps**:
1. Change responder field to array in model
2. Update database schema for multiple responders
3. Add primary/secondary responder designation
4. Update assignment logic for critical emergencies
5. Display all responders to patient
6. Test multi-responder scenarios

**Estimated time**: 14 hours

### Phase 3: Low Priority Improvements (Week 5)

#### 3.1 Assignment History and Analytics
**Files to modify**:
- `backend/src/repositories/assignment-history.repository.ts` (NEW) - Track history
- `lib/screens/admin_dashboard.dart` - Show analytics
- `backend/src/services/analytics.service.ts` (NEW) - Calculate metrics

**Steps**:
1. Create assignment history table
2. Log all assignment events
3. Create analytics service
4. Build analytics dashboard
5. Show response times, success rates, patterns
6. Test analytics accuracy

**Estimated time**: 12 hours

#### 3.2 Responder Preferences and Constraints
**Files to modify**:
- `lib/models/user_model.dart` - Add preferences
- `lib/screens/profile_screen.dart` - Add preference UI
- `backend/src/services/assignment.service.ts` - Use preferences

**Steps**:
1. Add preference fields to user model
2. Create preference management UI
3. Update assignment logic to respect preferences
4. Test with various preferences

**Estimated time**: 8 hours

---

## Testing Plan

### Unit Tests
- Proximity calculation accuracy
- ETA calculation accuracy
- Skill matching logic
- Workload balancing algorithm
- Timeout and escalation logic

### Integration Tests
- End-to-end automatic assignment
- Multi-responder assignment
- Reassignment flow
- Escalation notifications
- Preference-based assignment

### Manual Testing Scenarios
1. Create emergency - verify auto-assignment to closest responder
2. Test with 3 responders at different distances - verify closest assigned
3. Set responder to busy - verify not assigned
4. Create critical emergency - verify multi-responder assignment
5. Decline assignment - verify reassignment to next closest
6. Test timeout - verify escalation after timeout
7. Test ETA accuracy - compare with actual travel time
8. Test skill-based assignment - verify correct skill match
9. Test workload balancing - verify even distribution
10. Test preferences - verify respected

---

## Estimated Timeline

- **Phase 1**: 2 weeks (46 hours)
- **Phase 2**: 2 weeks (44 hours)
- **Phase 3**: 1 week (20 hours)
- **Testing**: 1 week (24 hours)
- **Total**: 6 weeks (134 hours)

---

## Risks and Mitigations

### Risk 1: Proximity calculation may be inaccurate
**Mitigation**: Use Google Maps Distance Matrix API, fallback to straight-line distance, allow manual override

### Risk 2: ETA may be inaccurate due to traffic
**Mitigation**: Use real-time traffic data, show "estimated" label, update in real-time, allow manual override

### Risk 3: Auto-assignment may assign to unavailable responder
**Mitigation**: Strict availability tracking, auto-update status, allow decline, quick reassignment

### Risk 4: Skill-based matching may have no matches
**Mitigation**: Fallback to any available responder, alert admin, expand search radius

### Risk 5: Workload balancing may be unfair
**Mitigation**: Consider responder preferences, allow manual override, track satisfaction

### Risk 6: Multi-responder assignment may cause confusion
**Mitigation**: Clear designation of primary/secondary, coordination tools, group chat

### Risk 7: Assignment timeout may be too short/long
**Mitigation**: Configurable timeouts, different timeouts by severity, admin override

### Risk 8: Reassignment may cause delays
**Mitigation**: Quick reassignment, notify patient of change, track reassignment time

---

## Success Metrics

- **Reduced assignment time**: From manual (varies) to <30 seconds automatic
- **Improved response time**: From 10min to 5min average
- **Increased assignment success rate**: From 90% to 98%
- **Reduced responder workload variance**: From high variance to balanced
- **Improved ETA accuracy**: Within 2 minutes of actual arrival
- **Reduced escalation rate**: From 10% to <5%
- **Increased responder satisfaction**: From 70% to 85%
- **Reduced patient anxiety**: Measured via feedback
