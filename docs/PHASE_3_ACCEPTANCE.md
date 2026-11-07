# Phase 3 shared-server acceptance runbook

**Status:** required before Phase 3 can be marked complete or tagged.

This runbook is for an authorised church/pilot operator with an Android device and a Windows 10/11 machine. It is intentionally separate from automated CI: the automated Android and Windows routes use a transport test double and cannot prove that two real clients reach the same deployed NestJS/PostgreSQL environment.

## Safety boundary

- Use an approved pilot/test environment over TLS, church-controlled test accounts and only authorised synthetic test records. Do not use production convert data.
- Both clients must use the **identical HTTPS API origin and path**, including `/api/v1/`. `localhost` is never valid for a physical phone because it points to the phone itself.
- Record the deployment version, non-secret API URL, test time window and the operator names/roles. Do not put access tokens, phone numbers, addresses or screenshots containing PII in the evidence log.
- If any test record is created, use the authorised consent flow and remove/anonymise it through the privacy workflow when the test is complete.

## Preflight

1. Deploy one NestJS API release and one PostgreSQL database. Confirm migrations are current and both devices can reach the same TLS health endpoint:

   ```text
   https://pilot.example.org/api/v1/health
   ```

2. Prepare a disposable hierarchy with two countries or otherwise isolated branches. The target branch must contain Country, Region, Province, Zone, Area and Parish. Prepare a sibling/out-of-scope branch with a sentinel record so scope boundaries can be proven.
3. Create active test identities with exactly the approved roles and home units:

   | Identity        | Required home scope | Expected UI scope                  |
   | --------------- | ------------------- | ---------------------------------- |
   | Global Admin    | Global              | All test countries/branches        |
   | Country Admin   | Target Country      | That country and descendants only  |
   | Region Leader   | Target Region       | That region and descendants only   |
   | Province Leader | Target Province     | That province and descendants only |
   | Zone Leader     | Target Zone         | That zone and descendants only     |
   | Area Leader     | Target Area         | That area and descendants only     |
   | Parish Pastor   | Target Parish       | That parish only                   |

   Prepare an Android and a Windows identity whose authorised scopes overlap at the target Area/Parish. A Soul Winner or other approved registration identity may be used for the two-way registration check when policy requires it.

4. Write down a single launch value before starting, for example:

   ```text
   API_BASE_URL=https://pilot.example.org/api/v1/
   ```

   Do not substitute a device-local hostname for either client.

## Launch the exact same client/server pairing

From a checkout of the release under test, bootstrap runners and resolve packages on each host. Then use the same `API_BASE_URL` literal for both launches.

```bash
# Android host/device
cd app
./tool/bootstrap_platforms.sh
flutter pub get
flutter run --dart-define=API_BASE_URL=https://pilot.example.org/api/v1/
```

```powershell
# Windows host
cd app
.\tool\bootstrap_windows.ps1
flutter pub get
flutter run -d windows --dart-define=API_BASE_URL=https://pilot.example.org/api/v1/
```

A physical Android phone must be able to resolve and trust the pilot certificate. For an emulator and Windows running on the same development host only, `10.0.2.2` and `localhost` can address that host respectively, but this does **not** satisfy the physical shared-server acceptance gate.

## Required evidence sequence

### 1. Android to Windows

1. Sign in on Android using the prepared authorised identity.
2. Submit one approved synthetic, consented decision. Give it a unique non-PII correlation label such as `P3-ANDROID-<timestamp>`.
3. On Windows, sign in using the overlapping authorised identity, refresh **Converts**, and confirm the exact correlation label appears once. Confirm the relevant scoped count changes once, not twice.
4. Capture the timestamp, device type, role and a redacted result in the acceptance record.

### 2. Windows to Android

1. Submit a different approved synthetic, consented decision from Windows, for example `P3-WINDOWS-<timestamp>`.
2. Refresh Android **Converts** and confirm the second label appears once.
3. Confirm the scoped count changes once and the record can be opened only where the signed-in role is authorised.

### 3. Hierarchy/UI scope proof

For each prepared identity, sign in through the client UI and record the visible hierarchy, convert list and dashboard count.

| Role            | Must see                                                        | Must not see                                                         |
| --------------- | --------------------------------------------------------------- | -------------------------------------------------------------------- |
| Global Admin    | Both target and sentinel branches; country selector/grand total | Nothing excluded by a non-global home scope                          |
| Country Admin   | Target Country subtree                                          | Sentinel country/branch                                              |
| Region Leader   | Target Region subtree                                           | A sibling region and sentinel country                                |
| Province Leader | Target Province subtree                                         | A sibling province and higher/sibling branches outside the home path |
| Zone Leader     | Target Zone subtree                                             | A sibling zone and branches outside the home path                    |
| Area Leader     | Target Area subtree and its parishes                            | A sibling area and branches outside the home path                    |
| Parish Pastor   | Target Parish records                                           | Parent/sibling parish records outside the parish scope               |

If a result differs from the table, stop the acceptance run, preserve only redacted evidence and open a defect. Do not work around a scope failure by changing the test user’s role.

### 4. Clean up

1. Use the authorised privacy/removal process to remove or anonymise the two synthetic decisions.
2. Recheck that the records no longer appear in normal lists and scoped roll-ups.
3. Revoke the disposable sessions/accounts if the pilot procedure requires it.

## Acceptance record

Complete this record outside the repository so no credentials or PII are committed.

| Item                                                                  | Record                                       |
| --------------------------------------------------------------------- | -------------------------------------------- |
| Date/time window and timezone                                         |                                              |
| Backend release/version                                               |                                              |
| Shared non-secret API URL                                             |                                              |
| Android model/OS and app build                                        |                                              |
| Windows version and app build                                         |                                              |
| Android → Windows result                                              | Pass / fail with redacted evidence reference |
| Windows → Android result                                              | Pass / fail with redacted evidence reference |
| Global, Country, Region, Province, Zone, Area and Parish scope checks | Pass / fail for each role                    |
| Test-record privacy cleanup                                           | Pass / fail                                  |
| Church/pilot operator approval                                        | Name, role, date                             |

Only after every required result is recorded as passing may Phase 3 be approved for tagging. This runbook does not replace release signing, production deployment review, provider credential governance or privacy/security approval.
