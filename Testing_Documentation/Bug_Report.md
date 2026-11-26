# RideAndServe — Defect Log, Bug Report & System Improvement Catalog

**Project Name:** RideAndServe — Smart Transport & Scheduled Ride Sharing Platform  
**Document Type:** Formal Software Defect Tracking & Known Issues Catalog  
**Version:** 1.0.0  
**Date:** November 2026  
**Audience:** FYP Project Supervisors, Examination Committee & Quality Assurance Engineers  

---

## 1. Defect Severity & Priority Classification

To maintain high software reliability standards, defects and system anomalies are categorized as follows:

| Severity Level | Definition | Impact on Release |
| :--- | :--- | :--- |
| **Critical / Blocker (S1)** | System crash, data loss, duplicate database writes, or inability to complete core user journeys. | Blocks production deployment or evaluation. |
| **Major (S2)** | Core functional failure with no direct workaround; inaccurate business calculations or broken socket channels. | Must be addressed before milestone delivery. |
| **Moderate (S3)** | Non-critical workflow failure or UI glitch with an available workaround. | Scheduled for subsequent sprint. |
| **Low / Enhancement (S4)** | Cosmetic defects, minor typography misalignments, or suggested feature additions. | Nice-to-have improvements. |

---

## 2. Discovered & Resolved Defects (Verification Log)

The following critical defects were identified during project analysis, isolated through root-cause analysis, and successfully resolved and verified in the source code.

---

### BUG-001: Premature Admin Notification on Per-Passenger Reason Selection

| Defect Attribute | Details |
| :--- | :--- |
| **Bug ID** | `BUG-001` |
| **Module** | Driver Mobile App — Incident Reporting (`report_issue_screen.dart`) |
| **Severity / Priority** | **S1 - Critical / P0 - Blocker** |
| **Status** | **RESOLVED & VERIFIED** |
| **Screen / File** | [`Frontend/lib/screens/driver/report_issue_screen.dart`](file:///c:/RideAndServe/Frontend/lib/screens/driver/report_issue_screen.dart) |

#### 1. Description & Steps to Reproduce
1. Driver opens **Report an Issue** from the dashboard.
2. Driver taps on a passenger card (e.g., *Ahmed Shah*) to specify an issue.
3. In the modal bottom sheet, the driver taps an issue tile (e.g., *Heavy Rain*).
4. **Observed Behavior (Defect):** The app immediately fired an asynchronous HTTP POST request to `/driver/report-issue` via an inline `_savePassengerIssueToDb(p)` function. As a result, the backend dispatched a real-time Socket.IO alert to the Admin before the driver ever pressed the "Send to Admin" button.
5. **Expected Behavior:** Tapping an issue reason inside the bottom sheet should only update local UI state (`p.canBePicked = false`, `p.reasonNote = "Heavy Rain"`). No network request should be sent until the driver explicitly clicks "Send to Admin".

#### 2. Root Cause Analysis
The bottom sheet's `GridView.builder` `onTap` handler and the "Mark as Can be picked" handler both executed `_savePassengerIssueToDb(p)` directly on tap.

#### 3. Resolution Applied
- Removed calls to `_savePassengerIssueToDb` from the dialog's `onTap` callbacks in [`report_issue_screen.dart`](file:///c:/RideAndServe/Frontend/lib/screens/driver/report_issue_screen.dart#L521-L529).
- Purged the orphaned body of `_savePassengerIssueToDb`.
- Reason selection now purely triggers `setState()` on the local `_PassengerItem` object.
- Network submission is strictly restricted to the primary `_submitIssue()` method triggered by the "Send to Admin" button.

---

### BUG-002: Duplicate Issue Report Creation via Route Aliases and Multi-Collection Sync

| Defect Attribute | Details |
| :--- | :--- |
| **Bug ID** | `BUG-002` |
| **Module** | Backend API — Driver Routes & Driver Controller |
| **Severity / Priority** | **S1 - Critical / P0 - Blocker** |
| **Status** | **RESOLVED & VERIFIED** |
| **Screen / File** | [`Backend/Route/driverRoute.js`](file:///c:/RideAndServe/Backend/Route/driverRoute.js#L79-L84) & [`Backend/Controller/Driver.js`](file:///c:/RideAndServe/Backend/Controller/Driver.js#L583-L587) |

#### 1. Description & Steps to Reproduce
1. Driver submits an issue report via the mobile client.
2. Inspect the MongoDB collections: `issuereports`, `driverissues`, `reportissues`, and `driverreports`.
3. **Observed Behavior (Defect):** A single report submission generated 4 documents in MongoDB across 4 different collections. In addition, `driverRoute.js` registered 3 identical route endpoints (`/report-issue`, `/report_issue`, `/issue`), creating duplicate webhooks and redundant network traffic.
4. **Expected Behavior:** A report submission must write exactly **one** canonical document to the `IssueReport` collection, with zero duplicate database writes.

#### 2. Root Cause Analysis
Lines 585–600 in `Driver.js` executed an explicit `Promise.allSettled()` inserting raw copies into `driverissues`, `reportissues`, and `driverreports`. Furthermore, three routes were assigned to the same handler in `driverRoute.js`.

#### 3. Resolution Applied
- Removed redundant route registrations from `driverRoute.js`, retaining only `POST /report-issue`.
- Removed the multi-collection insertion block from `Driver.js`.
- All queries and administrative interfaces now query the canonical `IssueReport` model exclusively.

---

### BUG-003: Unlinked RideRequest Caused by Ambiguous Passenger ID Format

| Defect Attribute | Details |
| :--- | :--- |
| **Bug ID** | `BUG-003` |
| **Module** | Frontend Model & Backend Database Synchronization |
| **Severity / Priority** | **S1 - Critical / P0 - Blocker** |
| **Status** | **RESOLVED & VERIFIED** |
| **Screen / File** | [`Frontend/lib/screens/driver/report_issue_screen.dart`](file:///c:/RideAndServe/Frontend/lib/screens/driver/report_issue_screen.dart#L39-L72) & [`Backend/Controller/Driver.js`](file:///c:/RideAndServe/Backend/Controller/Driver.js#L616-L640) |

#### 1. Description & Steps to Reproduce
1. Driver reports an issue for a passenger belonging to ride `REQ-8031`.
2. Inspect the `riderequests` collection in MongoDB.
3. **Observed Behavior (Defect):** The `RideRequest` document remained in status `ASSIGNED`, and `driverIssue` remained `null`. The backend reported success, but the ride was never marked as `Driver Unavailable`.
4. **Expected Behavior:** The specific `RideRequest` matching the reported passenger must update its status to `"Driver Unavailable"` and populate `driverIssue` with issue details.

#### 2. Root Cause Analysis
The frontend `_PassengerItem` class consolidated `_id` and `requestId` into a single `id` field. If `_id` was a MongoDB Hex string, the backend lookup `RideRequest.findOne({ requestId: pId })` failed to find a match.

#### 3. Resolution Applied
- Added an explicit `requestId` field to `_PassengerItem` in `report_issue_screen.dart`.
- The submission payload now explicitly passes `requestId`, `mongoId`, and `id`.
- Enhanced the backend lookup query in `Driver.js` to query across:
  1. `p.requestId` (e.g., `"REQ-8031"`)
  2. `p.mongoId` (MongoDB `ObjectId`)
  3. `p.id` (multi-format check)
  4. Top-level request body `requestId`

---

### BUG-004: Replacement Driver Inheriting Stale Issue Warnings upon Reassignment

| Defect Attribute | Details |
| :--- | :--- |
| **Bug ID** | `BUG-004` |
| **Module** | Backend Dispatch Controller & Driver Active Ride Screen |
| **Severity / Priority** | **S1 - Critical / P0 - Blocker** |
| **Status** | **RESOLVED & VERIFIED** |
| **Screen / File** | [`Backend/Controller/RideController.js`](file:///c:/RideAndServe/Backend/Controller/RideController.js#L484-L496) |

#### 1. Description & Steps to Reproduce
1. Driver A reports an issue for ride `REQ-8031`. Ride status becomes `Driver Unavailable`.
2. Admin opens dispatch console and reassigns ride `REQ-8031` to Driver B (`dispatchRide`).
3. Driver B receives the dispatch and opens the ride details screen.
4. **Observed Behavior (Defect):** Driver B's screen displayed a red banner with Driver A's old issue note ("Heavy rain at home"), confusing Driver B.
5. **Expected Behavior:** Driver B is a fresh replacement driver and must receive a clean ride state without stale issue alerts.

#### 2. Root Cause Analysis
In `RideController.js`, `dispatchRide()` updated `assignedDriverId` and set `status: "ASSIGNED"`, but failed to clear the existing `driverIssue` object on the `RideRequest` document.

#### 3. Resolution Applied
Updated `dispatchRide()` in `RideController.js` to explicitly set `driverIssue: null`:
```javascript
const updatedRide = await RideRequest.findByIdAndUpdate(
  existingRide._id,
  {
    status: "ASSIGNED",
    assignedDriverId: driverId || null,
    driverId: driverId || null,
    assignedDriverName: assignedName || "Assigned Driver",
    driverIssue: null // Explicitly cleared for fresh driver assignment
  },
  { returnDocument: 'after', new: true }
);
```

---

## 3. Potential Edge Cases & Recommended Future Enhancements

The following items are identified as architectural recommendations and potential edge cases for future sprints:

### POT-001: Offline Push Notification Delivery Fallback (FCM)
- **Component:** Notification Delivery Pipeline (`app.js`, `CustomerNotification.js`)
- **Category:** Architecture Enhancement (Non-Functional)
- **Observation:** Real-time alerts currently depend entirely on an active WebSocket connection via Socket.IO. If the mobile app is terminated or in deep sleep (backgrounded), the socket connection disconnects. While notifications persist in the database, the user does not receive a system tray heads-up notification.
- **Recommended Action:** Integrate Firebase Cloud Messaging (FCM) or Apple APNs to send native push notifications when the recipient socket is not actively connected.

### POT-002: Geocoding Rate Limiting on Rapid Pin Movement
- **Component:** `Frontend/lib/screens/customer/location_map_picker_modal.dart`
- **Category:** Usability & Performance Edge Case
- **Observation:** If a user rapidly moves the map pin across the screen, multiple reverse-geocoding HTTP requests are fired in short intervals.
- **Recommended Action:** Implement a 400ms debounce timer so geocoding only triggers after the pin has stopped moving for at least 400 milliseconds.

### POT-003: Ride History Offline Caching
- **Component:** `Frontend/lib/screens/driver/driver_ride_history_screen.dart`
- **Category:** Offline Resiliency
- **Observation:** If a driver opens Ride History while in an area with zero cellular connectivity, the screen shows a retry indicator rather than displaying previously cached trips.
- **Recommended Action:** Cache the last fetched history list in local SQLite or Hive storage so drivers can view past earnings while offline.

### POT-004: Multi-Currency & Locale Support
- **Component:** `Frontend/lib/screens/*` & `Backend/schema/RideRequest.js`
- **Category:** Internationalization (i18n)
- **Observation:** Currency symbols are currently hardcoded to `Rs.` (Pakistani Rupee).
- **Recommended Action:** Centralize currency rendering through an application-wide locale configuration helper to facilitate multi-currency deployments.

---

## 4. Defect Log Summary Matrix

| Defect ID | Title | Severity | Priority | Component | Status |
| :---: | :--- | :---: | :---: | :--- | :---: |
| **BUG-001** | Premature Admin Notification on Reason Selection | S1 | P0 | Driver Frontend | **RESOLVED** |
| **BUG-002** | Duplicate DB Records via Route Aliases & Multi-Sync | S1 | P0 | Backend API | **RESOLVED** |
| **BUG-003** | Unlinked RideRequest Due to Ambiguous ID Resolution | S1 | P0 | Frontend / Backend | **RESOLVED** |
| **BUG-004** | Stale driverIssue Retained on Reassigned Driver | S1 | P0 | Backend Dispatch | **RESOLVED** |
| **POT-001** | Native FCM Push Notification Fallback | S3 | P2 | Notification Engine | **OPEN / BACKLOG** |
| **POT-002** | Geocoding Debouncing on Interactive Map Picker | S3 | P2 | Customer Frontend | **OPEN / BACKLOG** |
| **POT-003** | Local Offline Caching for Driver Ride History | S3 | P3 | Driver Frontend | **OPEN / BACKLOG** |
| **POT-004** | Centralized Multi-Currency Config Helper | S4 | P3 | Core Architecture | **OPEN / BACKLOG** |

---
*End of Bug Report & Defect Tracking Document.*
