# Kokonuts Bookkeeping

Kokonuts Bookkeeping is a Flutter application. This is the latest commit. This README highlights how to build and ship it as an installable progressive web app (PWA).

## Getting Started

1. Install Flutter (3.19 or later) by following the [official instructions](https://docs.flutter.dev/get-started/install).
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app on a device or Chrome:
   ```bash
   flutter run
   ```

### Avoiding CORS issues on web

Browser builds now route requests through a CORS proxy by default to prevent cross‑origin failures when calling the CRM APIs from `localhost`. The proxy template defaults to `https://corsproxy.io/?`.

- To change or disable the proxy, pass a different value (or an empty string) via `--dart-define=CORS_PROXY_TEMPLATE=<value>` when running or building.
- The template should include `{url}` where the target URL should be injected, or end with `?`/`&` so the encoded target URL can be appended.

## Making the web build PWA-ready

The repository already contains a web manifest and the HTML hooks that Flutter uses to generate and register a service worker in release builds. To produce an installable PWA:

1. **Update branding (optional):** Replace `web/icons/*` with your own 192px and 512px icons. Maskable variants improve the install UI on Android.
2. **Verify manifest values:** `web/manifest.json` now includes an app id, scope, and human-friendly name so Lighthouse can detect installability.
3. **Build the offline-capable bundle:**
   ```bash
   flutter build web --release --pwa-strategy=offline-first
   ```
   The command emits `build/web/flutter_service_worker.js`, which caches app shell assets for offline use.
4. **Serve over HTTPS:** Deploy the contents of `build/web` behind HTTPS with correct MIME types (including `application/manifest+json` for `manifest.json`). Ensure the `base href` in `web/index.html` matches your hosting path if you serve from a subdirectory.
5. **Validate:** Open the deployed site in Chrome, check the install prompt (or open the “Install app” menu entry), and run Lighthouse → **Progressive Web App** to confirm the app is installable and uses the expected theme color.
