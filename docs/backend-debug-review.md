# New backend debug build

This branch builds a debug APK for review using the new self-hosted backend public configuration. It does not publish a release or use a production signing key.

The public API remains in maintenance until cutover verification is complete. Do not uninstall the existing application or delete its local data to install a review APK. Verify signing certificate compatibility first; CI debug signing can differ from the installed application.

Payment provider integration is deferred; no DOKU payment is created by this build.
