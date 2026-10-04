# UI redesign

All 43 screen files now use the warm-white and teal visual system. `app_theme.dart` supplies consistent typography and component styles; `minimal_ui.dart` supplies constrained tablet pages, scrollable authentication forms, branding and the PIN keypad.

Authentication and PIN layouts were rebuilt; settings now use a white account card and grouped rows; table cards distinguish vacant, occupied, requested bill and reserved states; food and retail grids adapt to screen width and text size. Unavailable items keep names/prices readable. The earlier home, cashier and payment redesign is included.

Primary palette: background #F7F9F8, surface #FFFFFF, text #172B2A, secondary text #62736F, action #00796B, border #DEE7E3. Status text uses darker semantic colors. No mock transaction data or preview images are inserted into the app.

Database services, providers, models, stock checks, permissions, login/PIN verification, shift operations and transaction calculations retain their existing implementation. Top-up continues to open the website dashboard; no new in-app top-up payment flow was introduced.

## Verification

Static analysis of the final screen files and two theme files reported zero errors; existing warnings and deprecation notices remain. Full-source analysis still reports 10 pre-existing errors in `core/services/supabase_db.dart`: incompatible empty-list return values and filtering after `.order()`. These backend errors were not modified by the UI work.

`test/minimal_ui_test.dart` covers small-screen/large-font PIN scrolling, disabled actions during validation, masked PIN semantics, and tablet content width. The local Flutter launcher could not execute these tests because SDK/system access was restricted. The tests are provided but are not claimed to pass.

This repository currently contains source files without the original pubspec, Android project or assets. No APK build or device screenshots have been verified. Merge this source into the complete Flutter project, resolve any remaining source errors, then run:

```sh
flutter pub get
flutter analyze
flutter test test/minimal_ui_test.dart
flutter run
flutter build apk --release
```

Test owner/staff/cashier login, PIN creation/verification/lockout, shifts, role access, branch switching, food/retail modes, small phones/tablets/large fonts, unavailable stock, cart/payment methods, promos, tables, platform/internal orders, printer flows, reports, subscriptions and offline operation on devices before release.
