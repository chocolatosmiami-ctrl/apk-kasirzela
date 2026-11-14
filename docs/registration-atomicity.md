# Owner registration consistency

Apply `sql/register-owner-atomic.sql` before deploying the `register-owner` Edge Function. The server adapter creates an Auth identity and then calls a service-only RPC that writes the owner and the existing trial subscription in one PostgreSQL transaction. Ordinary client JWTs cannot execute this RPC. It remains SECURITY INVOKER and requires no additional SQL access to Auth internals.

The handler returns success only after the business RPC returns an owner ID. A definite database rollback permits removal of the newly created Auth identity. A timeout or uncertain outcome retains Auth for reconciliation, because the database operation may already have committed. No Auth/database distributed transaction or automatic retry guarantee is claimed.

The original trial balance and transaction cost are preserved. Backend errors are returned as generic error codes; passwords, service credentials and database messages are not returned to clients.

Validation on 13 November 2026 used disposable, resource-limited containers without external networking and with dummy identities. The handler regression passed. Actual Auth/PostgREST checks confirmed ordinary-client denial, rollback of the owner after an injected subscription failure, successful registration and preservation of trial values. Auth/JWT/legacy migration and Realtime integration also completed successfully. No production accounts or payment-provider calls were used.

The SQL and Edge Function are source candidates, not an automatic deployment. Production/staging activation, public registration abuse controls, real email/payment delivery and actual app/website integration require separate verification. Never put the service key in the app or browser.
