# OpenAPI / Swagger publication

The running API publishes its OpenAPI document and interactive Swagger UI without requiring database data:

- Swagger UI: `GET /api/docs`
- OpenAPI JSON: `GET /api/docs-json`

For the default local prefix, these are `http://localhost:3000/api/docs` and `http://localhost:3000/api/docs-json`. The document is built from the Nest controllers and DTOs at service start, including authentication, Global Admin hierarchy/user/role endpoints, and RLS-scoped directory endpoints.

Protected operations display the **Authorize** button. Paste a short-lived access token obtained through `POST /api/v1/auth/otp/verify`; Swagger configures HTTP bearer/JWT authentication. Never paste a production refresh token or a church secret into Swagger.

The OpenAPI endpoints are documentation only. They do not weaken API guards, RLS, OTP throttling, session checks, role checks, or audit requirements. In a production gateway, decide deliberately whether `/api/docs` should be network-restricted; `/api/docs-json` is the machine-readable contract used by future client generation.

## Verification

After setting real non-placeholder environment values and running the API:

```bash
curl --fail http://localhost:3000/api/docs-json > /tmp/goye-openapi.json
python3 -c "import json; d=json.load(open('/tmp/goye-openapi.json')); print(d['openapi'], len(d['paths']))"
```

The Phase 1 verification run checks this live endpoint returns OpenAPI JSON and includes `/api/v1/auth/otp/request`, `/api/v1/admin/org-units/{id}`, and `/api/v1/directory/org-units`.
