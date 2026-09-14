# Chat Lite Android

A deliberately small Android chat client focused on smooth long conversations on Pixel-class phones.

## Performance rules

- Native Kotlin + Jetpack Compose; no WebView for the native chat path.
- `LazyColumn` renders only visible rows; the app additionally exposes only the latest 40 messages by default and loads older rows in 40-message pages.
- The active streamed answer lives in a separate `StateFlow`; completed message rows do not receive token-by-token state updates.
- Network deltas accumulate in a `StringBuilder` and publish to UI at most every 33 ms (~30 Hz).
- Streaming text is rendered as plain text. Expensive Markdown parsing is intentionally not on the hot path.
- Only the latest 20 messages are sent to the backend for a turn.
- Stop cancels the OkHttp call through Flow cancellation.

## Modes

1. **Account mode**: opens `https://chatgpt.com/` with the user's browser session, so the normal ChatGPT account/subscription remains available.
2. **Native Lite mode**: talks to the included Vercel backend. The backend uses Vercel AI Gateway; no OpenAI API key is stored in the Android app.

Default native model: `openai/gpt-5.6-luna`. `openai/gpt-5.6-sol` is available in Settings for harder tasks.

## Backend

Deploy the `backend/` directory as its own Vercel project and enable AI Gateway. Vercel deployments can authenticate AI Gateway with OIDC, so no provider key has to be shipped to the phone.

For personal deployments, set an optional `CHAT_LITE_TOKEN` environment variable. Enter the same value in Android Settings. This protects the proxy endpoint from casual public use; it is not an OpenAI API key.

## Build

This repository branch includes a GitHub Actions workflow that installs Gradle and Android SDK 37, runs `:app:assembleDebug`, and uploads `ChatLite-debug.apk` as a workflow artifact.
