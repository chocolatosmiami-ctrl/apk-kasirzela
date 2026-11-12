# Member identity on customer receipts

Member checkout already persisted customer identity in the durable order_sync_outbox JSON. The receipt model and renderers discarded it. Customer receipts now show Nama member and No. member in Bluetooth ESC/POS, PDF, text sharing and the receipt screen. Leading zeros are preserved. Ordinary transactions omit these rows. No points or discounts are invented.

Immediate food checkout carries its selected, verified member into the result model. Retail resolves the exact committed local ID/order number/account/branch, not the latest order. Missing receipt data produces a history/reprint prompt rather than a fabricated receipt from a cleared cart.

Local history reads the matching outbox payload, including acknowledged rows. Dart validates payload version and transaction/account/branch identity before extracting member fields. Server history keeps member_name/member_number; matching server metadata can enrich local receipts without replacing local financial totals, IDs or items. Old receipts without recorded member identity cannot infer it from the current member selection. No SQLite schema, SQL migration, authentication, API or payment calculation changes are required.

All receipt formats use the same validated member rows. Control characters are removed before rendering. Member names wrap in the PDF and screen; thermal printers use normal text wrapping. Kitchen tickets are unchanged.

## Verification

Trusted Dart SDK static analysis completed with 0 errors. Regression tests are authored in test/receipt_member_test.dart for leading zeros, ordinary receipts, persisted snapshots, transaction/account/branch mismatches, malformed JSON, printer control characters and financially safe reprint enrichment.

Tests, application builds, PDF rendering and printer/device runs were not executed: the security-audit skill requires an OS-enforced sandbox with no network, an allowlisted environment, read-only target/toolchain and resource quotas. This environment does not supply that complete isolation contract. Run flutter test test/receipt_member_test.dart in a suitable isolated environment, then test food/retail member checkout, nonmember checkout, restart/reprint and PDF/58mm/80mm printing. Verify long names and six-digit codes beginning with zero. No new APK was built here.
