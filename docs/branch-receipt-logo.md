# Branch-specific receipt logos

## Confirmed source issue and fix

The user reports the owner brand Dendeng Udasya on APK printed/PDF receipts while logged into Ayam Goreng Basah 88. A read-only database check confirmed that this branch already has its own struk_nama and logo_url. The existing RPC exposes those fields; no SQL/configuration change was needed.

The previous client fell back to the owner logo whenever branch metadata was absent, retained branch override fields across identity changes, restored only global settings, and reloaded a login only when the email changed. The owner-only cache did not identify a selected branch. The patch introduces account/owner/branch-bound branding snapshots and versioned startup settings keyed by the full identity including email/branch. Branch switching refreshes settings even with the same email. Auth notifications clear branding immediately; late replies cannot revive an older account or branch, including A-to-B-to-A switches.

A branch logo wins over the owner logo. A branch snapshot that explicitly has no logo retains the intended owner fallback. A branch whose settings have not been obtained does not establish that no override exists: display/print no logo until its own cache or server result is available. Legacy unscoped SQLite logos and startup cache entries are not used to identify the active brand. Existing per-branch branding cache can be reused offline; it never supplies stock, permissions or payment rules. Fresh server results replace removed logos as well as added ones.

Both PrinterService and PdfService already use effectiveLogoUrl, so the provider correction fixes their selection without separate bitmap/PDF rewrites. Cache keys for the printer already include URL and width. Existing receipt calculations, API parameters, SQLite schema and production backend endpoints are unchanged. Owner settings now use the owner ID already supplied by the verified profile rather than resolving another owner by email.

## Validation and limits

Trusted Dart SDK static analysis: 0 errors, 184 warnings (existing project warnings remain). Tests authored in test/branch_receipt_branding_test.dart cover branch override/fallback, scoped cache validation, delayed replies, A-B-A switching, offline cache, logout and malformed replies. They were not executed. The complete OS-enforced isolation contract required by the previously invoked security-audit skill is unavailable; its rule says: "If every control cannot be enforced, do not execute target code". Therefore no Flutter build/test, PDF rendering or physical printer run was performed here. A new APK was not built.

Desktop source files were backed up and synchronized; no app data, SQL, payments, login credentials or VPS services were changed. Device acceptance: install rebuilt APK as an update, log into the affected branch, print/share a new receipt, verify the branch logo; switch to another branch with the same owner/email, restart offline after a successful sync, and verify that branding does not leak across branches. Before the first successful branch fetch after this update, an unavailable backend can result in a missing logo, instead of printing the wrong owner brand.
