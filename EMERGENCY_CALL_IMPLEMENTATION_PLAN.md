# Emergency Caller <-> Responder Call Implementation Plan

## 1) Objective
Enable secure, real-time voice calling between:
- Requester: user who created the emergency request.
- Responder: responder who accepted or is actively assigned/responding.

The call feature should be fast to start, resilient to weak networks, and tightly scoped to the active emergency.

## 2) Scope (MVP)
- In-app one-to-one voice call.
- Call can only be started when an emergency is in `accepted` or `in_progress` state.
- Either side can initiate call; the other side gets an incoming-call prompt.
- Basic controls: mute/unmute, speaker toggle, end call.
- Call status visible in emergency timeline.

Out of scope for MVP:
- Video call.
- Group call or conference bridge.
- PSTN fallback (phone carrier dialing).

## 3) Suggested Technical Approach
## 3.1 Media stack
- Use WebRTC for peer-to-peer voice media.
- Flutter package: `flutter_webrtc`.

## 3.2 Signaling transport
- Reuse backend Node/TypeScript service with WebSocket signaling (Socket.IO or native WS).
- Signaling messages: offer, answer, ICE candidates, ring, accept, reject, end.

## 3.3 Session authority
- Backend remains the source of truth for:
- Who is allowed to call (authorization by emergency assignment).
- Active call session per emergency.
- Call lifecycle events and audit logs.

## 4) Data Model Changes
Add backend entities/tables (or collections):

### 4.1 `call_sessions`
- `id` (uuid)
- `emergency_id`
- `caller_user_id`
- `callee_user_id`
- `status` (`ringing`, `active`, `ended`, `missed`, `rejected`, `failed`)
- `started_at`
- `answered_at`
- `ended_at`
- `end_reason` (`hangup`, `timeout`, `network_error`, `rejected`)

### 4.2 `call_events` (optional but recommended)
- `id`
- `call_session_id`
- `event_type`
- `event_payload` (json)
- `created_at`

## 5) Backend API and Socket Contract
## 5.1 REST endpoints
- `POST /emergencies/:id/calls/start`
- Validate assignment and emergency state.
- Create `call_session` in `ringing`.
- Return `callSessionId` + signaling token/channel details.

- `POST /calls/:callSessionId/end`
- Mark ended and persist `end_reason`.

- `GET /emergencies/:id/calls/latest`
- For app resume/recovery.

## 5.2 WebSocket events
- Client -> Server
- `call:invite`
- `call:accept`
- `call:reject`
- `call:end`
- `webrtc:offer`
- `webrtc:answer`
- `webrtc:ice-candidate`

- Server -> Client
- `call:incoming`
- `call:ringing`
- `call:accepted`
- `call:rejected`
- `call:ended`
- `webrtc:offer`
- `webrtc:answer`
- `webrtc:ice-candidate`

## 6) Authorization and Security
- Only requester and assigned responder for the same emergency can join signaling room.
- Validate JWT on socket connect and on each call event.
- Use short-lived call-scoped token from `start` endpoint.
- Prevent parallel active calls for a single emergency (MVP: allow max one active call).
- Store minimal metadata; do not store voice content for MVP.

## 7) Flutter App Changes
## 7.1 New services
- Add `call_service.dart` (session creation, socket signaling, lifecycle).
- Add `webrtc_service.dart` (peer connection, tracks, ICE management).

## 7.2 Provider/state management
- Add `call_provider.dart` with state:
- `idle`, `outgoingRinging`, `incomingRinging`, `connecting`, `active`, `ended`, `error`.

## 7.3 UI screens/components
- Incoming call sheet/dialog with Accept/Reject.
- In-call screen:
- Responder/requester identity.
- Timer.
- Buttons: mute, speaker, end.
- Reconnect indicator for transient network drops.

## 7.4 Integration points in existing app
- `tracking_screen.dart`: add "Call Responder/Caller" CTA when allowed.
- `responder_dashboard.dart`: show incoming call prompt during active assignment.
- `timeline_screen.dart`: append call events (started, missed, ended).

## 8) Detailed Call Flow
1. Caller taps "Call" in active emergency.
2. App calls `POST /emergencies/:id/calls/start`.
3. Backend verifies authorization and creates `call_session`.
4. Backend emits `call:incoming` to callee.
5. Callee accepts -> `call:accept`; caller gets `call:accepted`.
6. WebRTC handshake over signaling:
- Caller sends offer.
- Callee sends answer.
- Both exchange ICE candidates.
7. Media connected -> both clients switch to `active`.
8. Either party ends -> `call:end`; backend persists end state; both clients close peer connection.

## 9) Failure Handling
- Ring timeout (e.g., 30s) -> mark `missed`.
- Rejected call -> mark `rejected` and notify caller.
- Socket disconnect during call -> try reconnect for 10-15s; if failed, end as `network_error`.
- App background/foreground restore -> query latest call state and reconcile UI.

## 10) Observability
- Metrics:
- call start attempts
- call answer rate
- median connect time
- call drop rate
- average call duration
- Structured logs keyed by `emergency_id` and `call_session_id`.
- Alert on high failure/drop rate.

## 11) Implementation Phases
### Phase 1: Foundations
- Add DB schema for call sessions/events.
- Add backend REST endpoints and socket namespace.
- Add auth checks and assignment validation.

### Phase 2: Flutter signaling + voice
- Implement `call_service.dart` and `webrtc_service.dart`.
- Wire provider state machine.
- Implement incoming and in-call UI.

### Phase 3: Reliability and UX hardening
- Handle reconnect and app lifecycle recovery.
- Add timeline integration and richer error messages.
- Add telemetry and dashboards.

### Phase 4: QA and rollout
- Internal test flights.
- Staged rollout by environment/feature flag.
- Monitor metrics and iterate.

## 12) Test Plan
## 12.1 Backend tests
- Authorization tests for invalid caller/callee/emergency state.
- Session lifecycle tests (`ringing -> active -> ended`).
- Timeout/reject/network-failure behaviors.

## 12.2 Flutter tests
- Provider state transitions.
- Incoming call UI and action buttons.
- Lifecycle recovery from background/resume.

## 12.3 End-to-end tests
- Real-device two-client call (Android-Android, iOS-iOS, Android-iOS).
- Poor network simulation (packet loss/high latency).
- Concurrent emergency scenarios.

## 13) Risks and Mitigations
- NAT traversal failures: configure STUN and optional TURN relay.
- Battery and background restrictions: keep signaling lean and lifecycle-aware.
- Notification latency: use push notification fallback if socket is unavailable.

## 14) Nice-to-Have (Post-MVP)
- Video escalation.
- Call recording with consent policy.
- Language translation assistant.
- Safety quick-actions (share live location during call).

