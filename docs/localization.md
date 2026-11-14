# Language and appearance

Fray supports English (`en`), Slovenian (`sl`) and Croatian (`hr`). The settings button on the sign-in screen and the controls under Profile change language and appearance immediately, without resetting the current form or signing out. Appearance options are Light, Dark and System. System is the initial setting for both preferences.

Preferences are local to each device/browser, stored with `SharedPreferencesAsync` under `fray.language` and `fray.theme`. They survive restarts and sign-out; they are not synced between devices or accounts. Startup reads them before displaying the app. Missing, unsupported or unreadable values fall back to System. Failed writes show an error and retain the previous setting. These preferences contain no credentials; native session cookies continue to use secure storage.

System language selects the first supported device locale, retaining regional formatting such as `en_GB`; unsupported languages fall back to English. Explicit selections use that language's default regional conventions. Dates, calendar weekday ordering and Material picker controls follow the selected locale. The phone's 12/24-hour preference still applies. Saved entry dates, UTC instants and original IANA timezones are unchanged. System appearance follows OS changes while the app is open. An explicit Light or Dark selection overrides the OS.

The UI catalog is `apps/fray/lib/l10n/translations.dart`: English source text maps to Slovenian and Croatian. `localization.dart` resolves it through Flutter's current `Localizations` locale and substitutes named placeholders once, so user content is never interpreted as another template. Add the same placeholders to every translation and use `context.tr(...)` (or the state mixin's `tr(...)`) for UI copy. Dynamic durations use `context.duration(...)`. Project names, descriptions, notes and sample demo content remain user data and are not translated. Theme colors come from Material's color scheme; project colors remain user-selected, with lighter text accents in dark mode. Authenticator QR codes retain a white background for scanning.

API requests send `Accept-Language`. Django's `LocaleMiddleware` selects English, Slovenian or Croatian for errors, password validation, CSV headings/type labels and verification emails. Each email uses the language selected when requesting it, including resend. JSON property names, enum values, dates and URLs remain stable. Mailjet credentials and a verified sender are still required for production signup; localization does not configure email delivery.

Backend catalogs live in `backend/locale/{sl,hr}/LC_MESSAGES/django.po`. Their compiled `.mo` files are committed so Docker does not need translation tools at runtime. After editing a catalog, regenerate it with GNU gettext:

```sh
msgfmt --check-format backend/locale/sl/LC_MESSAGES/django.po -o backend/locale/sl/LC_MESSAGES/django.mo
msgfmt --check-format backend/locale/hr/LC_MESSAGES/django.po -o backend/locale/hr/LC_MESSAGES/django.mo
```

Validation:

```sh
cd apps/fray
flutter analyze
flutter test
cd ../..
FRAY_DEBUG=1 .venv/bin/python backend/manage.py test tracker
```

`test/preferences_test.dart` checks persistence, invalid stored values, regional fallback, placeholder consistency, language switching without losing form input, live system theme/language changes, and all three languages in dark mode at 390px and 1440px. Existing picker and authentication tests remain in place. Backend tests check translated errors, password validation and real email-verification codes using the in-memory mail backend; no production email is sent.

For browser storage/reload checks, build the web app and launch `scripts/dev.py` locally, then run `scripts/preferences-browser-check.mjs` using the same Playwright environment variables as `scripts/browser-check.mjs`. It saves screenshots under `docs/screenshots/`.
