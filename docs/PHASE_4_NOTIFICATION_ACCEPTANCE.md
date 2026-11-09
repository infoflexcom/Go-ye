# Phase 4 real-notification acceptance evidence

> **Status: required before Phase 4 can be tagged.** Automated tests validate the queue, Android client route and Windows client route, but they cannot prove a real Firebase Cloud Messaging (FCM) delivery or a Windows toast on an authorised device.

Use only an authorised pilot/test hierarchy, test accounts and disposable consented records. Do not place real phone numbers, FCM registration tokens, service-account JSON, access/refresh tokens, private keys or convert notes in this document, Git, issue comments or screenshots.

## Prerequisites

1. Deploy one TLS-protected Go-Ye API/PostgreSQL environment and apply all migrations, including the Phase 4 follow-up migrations.
2. Use one shared `API_BASE_URL` on Android and Windows. Both devices must access the same deployed database through the API.
3. Church IT owns the Firebase project. Inject `FCM_ENABLED=true`, `FIREBASE_PROJECT_ID` and `FIREBASE_SERVICE_ACCOUNT_JSON` only through deployment secret storage. Do not commit `google-services.json`, Firebase service-account files or generated Firebase configuration.
4. Build/run Android with `--dart-define=FCM_ENABLED=true` plus the church Android app's `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID` and `FIREBASE_PROJECT_ID` values. Sign in with a Parish Pastor, Soul Winner or Follow-up Worker test account, grant notification permission and allow the app to register its FCM token.
5. Start the Windows client against the same URL and sign in with an authorised follow-up test account. Keep the client running so it can synchronise Today tasks and show its local toast.

## Exercise

1. Register a consented disposable convert at the Parish. Confirm the Today list shows the appropriate due task when it becomes due (use an authorised non-production test-time/data procedure if an accelerated schedule is needed).
2. Confirm Android receives one generic **Follow-up due** FCM notification. It must not expose the convert name, phone or note on the lock screen.
3. Confirm the running Windows client displays one generic local notification for the same server task. Confirm its task identity does not create additional visible notifications during repeated refreshes.
4. In Today on either platform, use **DONE** or record an outcome/note. Confirm the task leaves Today on both platforms after refresh and its completion appears in the authorised convert chronology.
5. Repeat the scheduler/delivery trigger or wait through at least one retry opportunity. Confirm the same task has no duplicate visible Android or Windows notification. The durable job uses one stable key; retain only a redacted job/task identifier suffix in evidence.
6. Clean up through the approved privacy/anonymisation workflow and confirm no disposable record remains in operational lists.

## Evidence to retain outside the repository

- Deployment/API URL host (redact internal host details if necessary), migration version and test window in UTC.
- Android device/OS/app version, notification-permission confirmation and a redacted screenshot/video of the FCM notification.
- Windows version/app version and a redacted screenshot/video of the local toast.
- Redacted Today/completion evidence from both clients, showing the same task identifier suffix and no PII.
- A statement from the authorised church operator that the two clients used one deployed backend/database and that no duplicate visible reminder occurred.

Phase 4 remains untagged until this evidence and the 30-day simulation are approved. This runbook does **not** replace the still-open Phase 3 shared Android/Windows data acceptance in [`PHASE_3_ACCEPTANCE.md`](PHASE_3_ACCEPTANCE.md).
