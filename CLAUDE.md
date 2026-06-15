# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Rails 8 app ("Q10 Extension — CLEV") that bridges the CLEV student access flow with **Q10** (academic/billing platform) and **Pagomedios** (Ecuadorian payment gateway). Student flow:

1. Student submits document type/number + email on the access form (`/`).
2. App validates the student against the Q10 API and emails a continuation link (signed token).
3. Link (`/continuar?token=...`) shows the student's Q10 debts; they pay via Pagomedios (`/pagar`).
4. On a successful Pagomedios webhook, the payment is recorded in Postgres and reported back to Q10.

UI is Spanish; keep user-facing strings, comments, and commit messages in Spanish to match the codebase.

## Commands

```bash
bin/setup                       # install deps + prepare DB (first time)
bin/dev                         # run server (alias for bin/rails server)
bin/rails server                # http://localhost:3000

bin/rails db:test:prepare test  # full test suite
bin/rails test test/services/q10/api_client_test.rb            # single file
bin/rails test test/services/q10/api_client_test.rb:42         # single test by line
bin/rails test:system           # Capybara/Selenium system tests (separate from `test`)

bin/rubocop                     # lint (rubocop-rails-omakase house style)
bin/brakeman                    # security scan
```

In development, outgoing mail does not use SMTP — view it at `/letter_opener`.

## Configuration

Env vars are loaded via `dotenv` (`.env`, copied from `.env.example`). Q10 settings are centralized in `config/q10.yml` (read with `Rails.application.config_for(:q10)`), all sourced from `Q10_*` env vars. Q10 is **disabled in the test environment** (`enabled: false`) — services raise `Q10::ApiClient::Error` when called while disabled, so tests stub the client. `Q10_ENABLED=false` toggles the integration off in dev/prod.

## Architecture

The HTTP flow is thin controllers (`home`, `q10_debts`, `payments`) delegating to service objects under `app/services/`. Key pieces and how they connect:

- **`Q10::ApiClient`** — wraps the Q10 REST API (`fetch_creditos`, `report_pago_credito`). It retries each request across several auth-header/query-param permutations (`perform_with_fallbacks` / `auth_attempts`) because the upstream gateway is inconsistent about how it expects the subscription key. When touching auth, preserve these fallbacks.
- **`Q10::LinkToken`** — generates/verifies the signed continuation-link token (`ActiveSupport::MessageVerifier`, SHA256, JSON, 2h expiry). This is how student context survives the email round-trip; not a DB record.
- **`PagomediosService`** — creates payment links against Pagomedios API v2. Amount math matters: the API requires `amount == amount_with_tax + amount_without_tax + tax_value`, each rounded to 2 decimals.
- **`PaymentSessionStore`** — caches the pending-payment context (credit IDs, reference, status) in `Rails.cache` (Solid Cache) keyed by `payment_session:<reference>`, TTL 7 days. This is the bridge between "payment created" and the later async webhook → it holds the Q10 credit context needed to report the payment. **Not** the `Payment` model.
- **`PaymentRecorder`** — persists the `Payment` ActiveRecord row through its lifecycle: `record_pending!` → `apply_webhook!` (Pagomedios result) → `apply_q10_report!` (Q10 reporting outcome).
- **`Q10::PaymentReporter`** / **`Q10::ReportOrchestrator`** — `ReportOrchestrator.report_and_record!` is the entry point after a confirmed webhook: it builds the Q10 payload from the cached session, reports it, records the result, and is idempotent (skips if already reported / missing context). `retry_report!(reference)` re-attempts from the cached session.

So a payment's state lives in **two** places that must stay in sync: the cached `PaymentSessionStore` (drives Q10 reporting) and the `Payment` row (durable record). The webhook handler is the join point.

## Background jobs, cache, cable

Uses the Solid stack (`solid_queue`, `solid_cache`, `solid_cable`) backed by Postgres, all in a **single** Heroku Postgres database. In production Solid Queue runs inside Puma (`SOLID_QUEUE_IN_PUMA=true`).

## Deployment (Heroku)

`Procfile` runs Puma (`web`) and, on each release, `rails heroku:release` (`lib/tasks/heroku_release.rake`). That task runs `db:prepare`, then conditionally loads `db/{queue,cache,cable}_schema.rb` only when the corresponding Solid marker table is missing — this avoids `ProtectedEnvironmentError` while still bootstrapping the Solid tables on a fresh single-DB Heroku setup. If you change the Solid schema files, this task is what installs them in production.
