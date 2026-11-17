# agentos_auth

[中文文档](README-zh_CN.md)

OAuth2 authentication SDK for AgentOS native clients. It supports two sign-in flows:

| Scenario | Flow | Typical client |
|----------|------|----------------|
| A fixed callback address is available | **Authorization Code + PKCE** (loopback / custom scheme) | Desktop |
| No fixed `redirect_uri` (for example a LAN IP that changes) | **Device Code** (RFC 8628) | Embedded / WebShell |

Both flows share one `AuthClient`, one session model and one token storage, and also provide token refresh and sign-out. The application decides which flow to use.

## Features

- **Authorization Code + PKCE (S256)**: no `client_secret`; a loopback HTTP server with a local HTML page handles the callback by default.
- **Device Code**: the device starts the authorization, the user confirms in a browser, and the client polls for the token. `scope` is **not sent by default** to avoid `invalid_scope` errors from the authorization server.
- **Session persistence**: in-memory cache plus configurable local storage (`serverAddress` + token).
- **Session restore**: restore the signed-in state from local storage when the app starts.
- **Token refresh**: exchange a `refresh_token` for a new `access_token`.
- **Cancel sign-in (redirect flow)**: `cancelOAuthLogin()` closes the loopback server and aborts the wait.
- **Two sign-out modes**:
  - `logout()` calls `GET /api/v1/auth/logout` to revoke the server-side tokens, then clears local state.
  - `logoutLocal()` only clears the local session without calling the server.

> Business APIs (user profile, model lists, ...) are out of scope for this SDK. Call them from your application or from a separate API package.

## Installation

```yaml
dependencies:
  agentos_auth: ^1.0.0
```

```bash
dart pub get
```

Requirements: Dart SDK `^3.13.0`.

## Server endpoints

Configure the plain server origin, without a path prefix or trailing slash:

```text
https://your-server.example.com
```

Do not append `/agentos-server`; the SDK adds it automatically:

| Purpose | Method | Path |
|---------|--------|------|
| Authorization page (redirect flow) | GET (opened in a browser) | `/agentos-server/oauth2/authorize` |
| Device authorization | POST | `/agentos-server/oauth2/device_authorization` |
| Token exchange / refresh / device-code polling | POST | `/agentos-server/oauth2/token` |
| Token revocation | POST | `/agentos-server/oauth2/revoke` |
| Sign-out | GET | `/agentos-server/api/v1/auth/logout` |

### Default OAuth client

| Setting | Default |
|---------|---------|
| `client_id` | `agentos-desktop` |
| `redirect_uri` (redirect flow only) | `http://127.0.0.1:53682/oauth/callback` |
| `scope` (sent by the redirect flow) | `openid profile email phone agentos.read agentos.write` |
| `prompt` (redirect flow) | `login` (re-authentication is required every time) |
| Device authorization path | `/oauth2/device_authorization` |

Override `clientId`, the redirect address, the scope, `deviceAuthorizationPath` and more through `OAuthConfig`.

The authorization server must register this redirect URI for the redirect flow: `http://127.0.0.1:53682/oauth/callback`. The device-code flow does **not** need a fixed `redirect_uri`.

For sign-out, send `Authorization: Bearer <access_token>`. With a valid token the server revokes the access and refresh tokens; without one (or with an invalid one) the call still succeeds but already issued tokens may not be revoked.

## Flow 1: Authorization Code + PKCE (Desktop)

### One-call sign-in (recommended)

```dart
import 'dart:io';
import 'package:agentos_auth/agentos_auth.dart';

Future<void> main() async {
  const serverAddress = 'https://your-server.example.com';

  final client = AuthClient();
  await client.initialize(serverAddress: serverAddress);

  if (client.isAuthenticated) {
    print('Session restored');
    return;
  }

  final token = await client.loginWithOAuth(
    serverAddress: serverAddress,
    openAuthorizationUrl: (url) async {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
      }
    },
  );

  print('Signed in: ${token.accessToken}');
}
```

`loginWithOAuth` will:

1. Generate the PKCE verifier and `state`, and build the authorization URL (including `prompt=login`).
2. Start a loopback server on `127.0.0.1:53682`.
3. Open the browser for authorization.
4. Wait for `/oauth/callback?code=...`, exchange the code for a token and persist the session.

### Loopback callback and browser success page

All platforms use **loopback + a local HTML page** by default (`OAuthRedirectTransport.loopback`).

1. The SDK completes the sign-in as soon as `/oauth/callback` receives the `code`; it does not wait for the user to interact with the success page.
2. The browser is then redirected (302) to `/oauth/login/success`, whose address bar contains neither `code` nor `state`.
3. The success page offers two buttons: **Back to AgentOS** (opens `agentos://open`, which requires the app to register that scheme) and **Close tab** (`window.close()`). There is no automatic close countdown.

| Path | Description |
|------|-------------|
| `/oauth/callback` | OAuth `redirect_uri`, carries `code` / `state` |
| `/oauth/login/success` | Sign-in success HTML page |
| `/oauth/logout/success` | Sign-out success HTML page |

### Cancel sign-in

```dart
await client.cancelOAuthLogin();
```

Call it while waiting for authorization. It closes the loopback server and throws `OAuthLoginCancelledException`.

### Step-by-step sign-in

```dart
final session = client.beginOAuthLogin(serverAddress: serverAddress);
// Open session.authorizationUrl yourself and obtain the callback Uri.
final token = await client.completeOAuthLogin(
  session: session,
  callbackUri: callbackUri,
);
```

### Optional: custom-scheme callback

The SDK keeps `OAuthRedirectTransport.customScheme` and `OAuthRedirectHandler`, so `redirect_uri` can be set to `agentos://oauth/callback`. It is **not enabled by default**; Desktop uses loopback.

## Flow 2: Device Code (Embedded / LAN)

Use it where a fixed `redirect_uri` is impossible, for example when a device is reached through a LAN IP that can change.

```dart
final client = AuthClient();
await client.initialize(serverAddress: serverAddress);

final session = await client.beginDeviceCodeLogin(
  serverAddress: serverAddress,
  config: const OAuthConfig(/* override clientId, ... if needed */),
);

// Open session.verificationUriComplete (or verificationUri and show user_code).
await openUrl(session.verificationUriComplete);

var interval = Duration(seconds: session.interval);
while (!session.isExpired) {
  await Future<void>.delayed(interval);
  final result = await client.pollDeviceCode(session: session);

  switch (result.status) {
    case DeviceCodePollStatus.complete:
      print('Signed in: ${result.token!.accessToken}');
      return;
    case DeviceCodePollStatus.pending:
      if (result.slowDown) {
        interval += const Duration(seconds: 5); // keep it below ~30s
      }
      break;
    case DeviceCodePollStatus.expired:
    case DeviceCodePollStatus.error:
      throw Exception(result.error ?? result.status.name);
  }
}
```

Notes:

1. `scope` is omitted by default; if your authorization server requires it, call `beginDeviceCodeLogin(includeScope: true)`.
2. Use the `interval` returned by the server and increase it when `slow_down` is received. Common error codes are `authorization_pending`, `slow_down` and `expired_token`.
3. On success `pollDeviceCode` persists the session automatically, exactly like the redirect flow.
4. If the server returns a `verification_uri` without a port, rewrite it in your application according to the real `serverAddress` before opening the browser; the SDK passes it through unchanged.

## Refresh, sign-out and storage

```dart
// Refresh the token.
if (client.currentToken?.isExpired == true) {
  await client.refreshToken();
}

// Sign out on the server and clear the local session (recommended).
await client.logout();

// Clear the local session only.
await client.logoutLocal();
```

`AuthToken.isExpired` reports true 60 seconds before `expiresAt`. `refreshToken` and `logout` accept a custom `OAuthConfig`, for example when an embedded product uses a different `clientId`.

By default the session is stored in a JSON file (see below). Pass `storagePath` to change the file location, or pass your own `TokenStorage` implementation, for example to keep the session in memory only or in a system secure store:

```dart
class MyTokenStorage implements TokenStorage {
  @override
  Future<void> saveSession(AuthSession session) async { /* ... */ }

  @override
  Future<AuthSession?> loadSession() async => null;

  @override
  Future<void> clearSession() async { /* ... */ }

  @override
  Future<bool> hasSession() async => false;
}
```

Default storage location:

- macOS / Linux: `~/.agentos/auth/session.json`
- Windows: `%USERPROFILE%\.agentos\auth\session.json` or `%APPDATA%\.agentos\auth\session.json`

For stricter security requirements, plug a system secure store in through `TokenStorage`.

## Architecture

| Module | Description |
|--------|-------------|
| `AuthClient` | OAuth sign-in (redirect / device code), refresh and sign-out |
| `OAuthConfig` / `OAuthDefaults` | Client ID, callback address, device authorization path, ... |
| `DeviceCodeSession` / `DeviceCodePollResult` | Device-code session and polling result |
| `LoopbackRedirectServer` | Local HTTP server and HTML success pages (redirect flow) |
| `OAuthRedirectTransport` | How the callback is received (loopback by default) |
| `OAuthRedirectHandler` | Optional custom-scheme callback injection |
| `Pkce` | PKCE and `state` generation |
| `AuthSession` / `AuthToken` | Session and token models |
| `TokenStorage` | Persistence abstraction |

## Try the example

Edit the `_serverAddress` constant at the top of `example/example.dart`, then run:

```bash
dart run example/example.dart
dart run example/example.dart logout
```

macOS, Linux and Windows try to open the browser automatically and print the authorization URL if that fails. The example demonstrates the **Authorization Code + loopback** flow.

## Caveats

- The server address is configured by the application; the SDK does no service discovery.
- Pick one flow per product entry point: redirect for Desktop / fixed callbacks, device code for Embedded / LAN. Do not mix both UIs.
- Redirect flow: sign-in fails if port `53682` is occupied; free it, or change `OAuthConfig.redirectPort` and register the same address on the server.
- Redirect flow: sign-in completes as soon as `/oauth/callback` is reached. The application should not steal browser focus at that moment; the user returns from the success page.
- Redirect flow: after a successful login the authorization server's login page must redirect back to `/oauth2/authorize` (with the `redirect` parameter). Otherwise the browser only shows the site's own "signed in" page and the loopback server never receives the `code`.
- Device-code flow: handle `authorization_pending`, `slow_down` and `expired_token` while polling.
