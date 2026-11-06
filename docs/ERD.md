# Go-Ye initial ERD

**Status:** Phase 0 logical model only. No schema migration exists yet and no real data may be stored.

The diagram establishes the entities and ownership boundaries required before the Phase 1 migration design. It is deliberately implementation-neutral: every physical table, constraint, index, row-level-security policy and rollback note will be introduced by versioned migration.

```mermaid
erDiagram
    ORG_UNITS {
        uuid id PK
        enum type "COUNTRY|REGION|PROVINCE|ZONE|AREA|PARISH"
        string name
        string code UK
        uuid parent_id FK
        ltree path
        boolean is_active
    }
    USERS {
        uuid id PK
        uuid home_unit_id FK "NULL only for Global Admin"
        string phone_or_email UK
        enum status
    }
    USER_ROLES {
        uuid user_id FK
        enum role
    }
    ACCESS_GRANTS {
        uuid id PK
        uuid recipient_user_id FK
        uuid parish_id FK
        uuid granted_by FK
        datetime expires_at
    }
    CONSENTS {
        uuid id PK
        string notice_version
        datetime captured_at
        uuid captured_by FK
        string capture_locale
        boolean affirmed
    }
    CONVERTS {
        uuid id PK
        uuid registered_at_unit_id FK
        uuid registered_by FK
        uuid parish_id FK "nullable until assigned"
        uuid consent_id FK
        bytes encrypted_phone
        bytes encrypted_address
        enum current_stage
        datetime decision_at
        enum privacy_status
        int revision
    }
    CONVERT_EVENTS {
        uuid id PK
        uuid convert_id FK
        uuid actor_id FK
        string event_type
        datetime occurred_at
    }
    FOLLOW_UP_PLANS {
        uuid id PK
        uuid convert_id FK
        string schedule_version
        boolean active
    }
    FOLLOW_UP_TASKS {
        uuid id PK
        uuid plan_id FK
        uuid assignee_id FK
        datetime due_at
        enum status
        string idempotency_key UK
    }
    TRACTS {
        uuid id PK
        string status
        string default_language
    }
    TRACT_TRANSLATIONS {
        uuid id PK
        uuid tract_id FK
        string locale
        string media_url
    }
    SHARE_LINKS {
        uuid id PK
        uuid tract_id FK
        uuid shared_by FK
        string public_token UK
    }
    SHARE_EVENTS {
        uuid id PK
        uuid share_link_id FK
        string event_type
        datetime occurred_at
    }
    UNIT_DAILY_SUMMARIES {
        uuid unit_id FK
        date summary_date
        int decisions_count
        int follow_up_completed_count
    }
    AUDIT_LOG {
        uuid id PK
        uuid actor_id FK
        string action
        string resource_type
        uuid resource_id
        string prior_hmac
        string event_hmac
        datetime occurred_at
    }

    ORG_UNITS ||--o{ ORG_UNITS : parents
    ORG_UNITS ||--o{ USERS : homes
    USERS ||--o{ USER_ROLES : holds
    USERS ||--o{ ACCESS_GRANTS : receives
    ORG_UNITS ||--o{ ACCESS_GRANTS : scopes
    ORG_UNITS ||--o{ CONVERTS : registers_at
    ORG_UNITS ||--o{ CONVERTS : assigns_to_parish
    USERS ||--o{ CONVERTS : registers
    CONSENTS ||--|| CONVERTS : authorises
    CONVERTS ||--o{ CONVERT_EVENTS : has
    CONVERTS ||--o| FOLLOW_UP_PLANS : follows
    FOLLOW_UP_PLANS ||--o{ FOLLOW_UP_TASKS : schedules
    USERS ||--o{ FOLLOW_UP_TASKS : assigned
    TRACTS ||--o{ TRACT_TRANSLATIONS : translated_as
    TRACTS ||--o{ SHARE_LINKS : shared_as
    USERS ||--o{ SHARE_LINKS : creates
    SHARE_LINKS ||--o{ SHARE_EVENTS : records
    ORG_UNITS ||--o{ UNIT_DAILY_SUMMARIES : rolls_up_to
    USERS ||--o{ AUDIT_LOG : acts
```

## Mandatory physical-model constraints for Phase 1

- `org_units` permits only `COUNTRY > REGION > PROVINCE > ZONE > AREA > PARISH`; migrations must reject invalid parent types and cycles.
- `path` uses an indexed `ltree` label derived from stable IDs. Unit moves rebuild the entire affected subtree transactionally and write an audit event.
- A convert has one `registered_at_unit_id` and one `registered_by`; `parish_id` may be null only while unassigned. Assignment creates/activates the parish follow-up plan.
- A positive consent record and consent metadata must exist before a convert insert is accepted.
- Phone/address ciphertext, not plaintext, is stored. Protected duplicate matching and key rotation need their own reviewed design.
- Audit records omit PII and form a verifiable HMAC chain.
- Summaries are derived/incremental facts; they are never the sole source of convert truth.
- RLS and API query predicates enforce home-unit-plus-descendant access. Above-parish detail reads create audit records in the same transaction.
