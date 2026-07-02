# agentos-auth

AgentOS OAuth2 认证 SDK，面向桌面端等原生客户端，提供 **Authorization Code + PKCE + Loopback 本地 HTML** 登录、Token 刷新与登出。

## 功能特性

- **OAuth2 登录**：Authorization Code + PKCE（S256），无 `client_secret`
- **Loopback 回调**：固定监听 `http://127.0.0.1:53682`，浏览器展示本地 HTML 成功页
- **会话持久化**：内存缓存 + 可配置本地存储（`serverAddress` + Token）
- **自动恢复**：应用启动时从本地恢复登录状态
- **刷新 Token**：使用 `refresh_token` 换取新的 `access_token`
- **取消登录**：`cancelOAuthLogin()` 关闭 loopback 并中止等待
- **两种登出**：
  - **本地登出** `logoutLocal()` / `logout()`：仅清除本机会话
  - **远端登出** `logoutRemote()`：浏览器清理 SSO → 撤销 Token → 清本地

> 业务 API（如用户信息、模型列表）不在本 SDK 范围内，由应用层或独立 API 包调用。

## 服务端接口（对齐 agentos-server）

配置纯服务器地址，不含末尾斜杠，例如：

```text
https://your-server.example.com
```

SDK 直接请求以下路径（**不走** `/liteAgent` 前缀）：

| 用途 | 方法 | 路径 |
|------|------|------|
| 授权页 | GET（浏览器打开） | `/oauth2/authorize` |
| 换 Token | POST | `/oauth2/token` |
| 刷新 Token | POST | `/oauth2/token` |
| 撤销 Token | POST | `/oauth2/revoke` |
| 远端登出 | GET（浏览器跳转） | `/api/v1/auth/logout` |

### 默认 OAuth 客户端

| 配置项 | 默认值 |
|--------|--------|
| `client_id` | `agentos-desktop` |
| `redirect_uri` | `http://127.0.0.1:53682/oauth/callback` |
| `scope` | `openid profile email phone agentos.read agentos.write` |
| `prompt` | `login`（每次授权要求重新认证） |

可通过 `OAuthConfig` 覆盖 `clientId`、回调地址、scope 等。

### 后端需登记的 redirect 地址

| 用途 | URL |
|------|-----|
| OAuth 登录回调 | `http://127.0.0.1:53682/oauth/callback` |
| 远端登出回跳 | `http://127.0.0.1:53682/oauth/logout/success` |

`post_logout_redirect_uri` 的 scheme + host + port 须与已登记 redirect 同源。

### 授权（浏览器）

```text
GET /oauth2/authorize
  ?response_type=code
  &client_id=agentos-desktop
  &redirect_uri=http://127.0.0.1:53682/oauth/callback
  &scope=openid profile email ...
  &state={state}
  &code_challenge={S256}
  &code_challenge_method=S256
  &prompt=login
```

### 换 Token / 刷新

```text
POST /oauth2/token
Content-Type: application/x-www-form-urlencoded

# 授权码换 Token
grant_type=authorization_code
&client_id=agentos-desktop
&code={code}
&redirect_uri=http://127.0.0.1:53682/oauth/callback
&code_verifier={verifier}

# 刷新
grant_type=refresh_token
&client_id=agentos-desktop
&refresh_token={refresh_token}
```

响应字段（节选）：`access_token`、`refresh_token`、`expires_in`、`token_type`。

### 登出

**本地登出**：SDK 清除内存与本地文件，不请求服务端。

**远端登出**：

```text
GET /api/v1/auth/logout
  ?client_id=agentos-desktop
  &post_logout_redirect_uri=http://127.0.0.1:53682/oauth/logout/success
```

流程：浏览器打开登出 URL（携带 cookie 清 SSO）→ loopback 等待回跳 → `POST /oauth2/revoke` 撤销 access_token → 清本地会话。

## Loopback 与浏览器成功页

默认全平台使用 **loopback + 本地 HTML**（`OAuthRedirectTransport.loopback`）。

### 登录回调时序

```text
App                 Loopback :53682              Browser           AgentOS Server
 |                        |                        |                      |
 |-- start loopback ----->|                        |                      |
 |-- open authorize URL -------------------------->|                      |
 |                        |                        |-- /oauth2/authorize ->|
 |                        |<-- /oauth/callback?code=... -------------------|
 |<-- 收到 code，换 token -|                        |                      |
 |                        |-- 302 /oauth/login/success ------------------>|
 |                        |                        |   （展示成功页）      |
```

要点：

1. SDK 在 **`/oauth/callback` 收到 `code` 时即完成登录**，不等待用户操作成功页
2. 浏览器随后 302 到 **`/oauth/login/success`**，地址栏不含 `code` / `state`
3. 成功页提供两个按钮：
   - **返回 AgentOS**：跳转 `agentos://open`（由 Desktop 唤起应用，需应用注册该 scheme）
   - **关闭标签页**：手动 `window.close()`
4. **无自动关闭倒计时**

### 路径一览

| 路径 | 说明 |
|------|------|
| `/oauth/callback` | OAuth `redirect_uri`，带 `code` / `state` |
| `/oauth/login/success` | 登录成功 HTML 页 |
| `/oauth/logout/success` | 登出成功 HTML 页 |

## 安装

```yaml
dependencies:
  agentos_auth:
    path: ../agentos-auth
```

```bash
dart pub get
```

## 使用指南

### 一键登录（推荐）

```dart
import 'dart:io';
import 'package:agentos_auth/agentos_auth.dart';

Future<void> main() async {
  const serverAddress = 'https://your-server.example.com';

  final client = AuthClient();
  await client.initialize(serverAddress: serverAddress);

  if (client.isAuthenticated) {
    print('已恢复会话');
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

  print('登录成功: ${token.accessToken}');
}
```

`loginWithOAuth` 内部会：

1. 生成 PKCE / state，拼授权 URL（含 `prompt=login`）
2. 在 `127.0.0.1:53682` 启动 loopback
3. 打开浏览器授权
4. 等待 `/oauth/callback?code=...`，换取 Token 并持久化

### 取消登录

```dart
await client.cancelOAuthLogin();
```

等待授权过程中可调用，会关闭 loopback 并抛出 `OAuthLoginCancelledException`。

### 分步登录

```dart
final session = client.beginOAuthLogin(serverAddress: serverAddress);
// 自行打开 session.authorizationUrl，并拿到回调 Uri
final token = await client.completeOAuthLogin(
  session: session,
  callbackUri: callbackUri,
);
```

### 刷新 Token

```dart
if (client.currentToken?.isExpired == true) {
  await client.refreshToken();
}
```

`AuthToken.isExpired` 在 `expiresAt` 前 60 秒即视为过期。

### 登出

```dart
// 仅清本地
await client.logoutLocal();

// 远端登出（浏览器 + 撤销 token + 清本地）
await client.logoutRemote(
  openLogoutUrl: (url) async {
    await Process.run('open', [url]);
  },
);

// 仅拼登出 URL
final url = client.buildLogoutUrl(
  serverAddress: serverAddress,
  postLogoutRedirectUri: const OAuthConfig().postLogoutRedirectUri,
);
```

### 仅内存（不落盘）

```dart
final client = AuthClient(tokenStorage: null);
await client.loginWithOAuth(
  serverAddress: serverAddress,
  openAuthorizationUrl: openUrl,
);
```

### 自定义存储

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

## 架构概览

| 模块 | 说明 |
|------|------|
| `AuthClient` | OAuth 登录、刷新、登出 |
| `OAuthConfig` / `OAuthDefaults` | 客户端 ID、回调地址、路径常量 |
| `LoopbackRedirectServer` | 本地 HTTP 服务 + HTML 成功页 |
| `OAuthRedirectTransport` | 回调承载方式（默认 loopback） |
| `OAuthRedirectHandler` | 可选自定义 Scheme 回调注入 |
| `Pkce` | PKCE / state |
| `AuthSession` / `AuthToken` | 会话与 Token 模型 |
| `TokenStorage` | 持久化抽象 |

### 默认存储位置

- macOS / Linux：`~/.agentos/auth/session.json`
- Windows：`%USERPROFILE%\.agentos\auth\session.json` 或 `%APPDATA%\.agentos\auth\session.json`

## 可选：自定义 Scheme 回调

SDK 保留 `OAuthRedirectTransport.customScheme` 与 `OAuthRedirectHandler`，可将 `redirect_uri` 设为 `agentos://oauth/callback`。当前 **默认未启用**，Desktop 使用 loopback。

成功页上的「返回 AgentOS」按钮会跳转 `agentos://open`，用于从浏览器手动唤起应用（需 Desktop 注册 `agentos://` scheme）。

## 注意事项

- 服务器地址由应用层配置，SDK 不做服务发现
- 端口 `53682` 被占用时登录失败，需释放或修改 `OAuthConfig.redirectPort` 并与后端登记一致
- 登录在收到 `/oauth/callback` 后即完成；应用不应在此时强制抢浏览器焦点，由用户在成功页自行返回
- 认证中心登录页须在成功后正确跳回 `/oauth2/authorize`（携带 `redirect` 参数），否则浏览器只显示网站内「登录成功」而 loopback 收不到 `code`
- 更高安全要求时，可通过 `TokenStorage` 接入系统安全存储
