# agentos_auth

[English](README.md)

AgentOS OAuth2 认证 SDK，面向原生客户端，提供两种登录方式：

| 场景 | 流程 | 典型终端 |
|------|------|----------|
| 固定回调可用 | **Authorization Code + PKCE**（Loopback / 自定义 Scheme） | Desktop |
| 无固定 `redirect_uri`（如 LAN IP 会变） | **Device Code**（RFC 8628） | Embedded / WebShell |

并提供 Token 刷新与登出。两种流程共用同一 `AuthClient`、会话模型与存储；由应用层选择调用哪套 API。

## 功能特性

- **Authorization Code + PKCE（S256）**：无 `client_secret`；默认 Loopback 本地 HTML 回调
- **Device Code**：设备发起授权 → 用户在浏览器确认 → 客户端轮询换 Token；默认**不传 `scope`**（避免认证中心 `invalid_scope`）
- **会话持久化**：内存缓存 + 可配置本地存储（`serverAddress` + Token）
- **自动恢复**：应用启动时从本地恢复登录状态
- **刷新 Token**：使用 `refresh_token` 换取新的 `access_token`
- **取消登录（Redirect 流）**：`cancelOAuthLogin()` 关闭 loopback 并中止等待
- **两种登出**：
  - **登出** `logout()`：`GET /api/v1/auth/logout` 撤销服务端 Token → 清本地
  - **仅本地** `logoutLocal()`：不请求服务端，只清除本机会话

> 业务 API（如用户信息、模型列表）不在本 SDK 范围内，由应用层或独立 API 包调用。

## 服务端接口（对齐 agentos-server）

配置纯服务器域名，不含路径前缀与末尾斜杠，例如：

```text
https://your-server.example.com
```

不要填写 `/agentos-server`；SDK 请求时会自动拼到 `{域名}/agentos-server` 下：

| 用途 | 方法 | 路径 |
|------|------|------|
| 授权页（Redirect 流） | GET（浏览器打开） | `/agentos-server/oauth2/authorize` |
| Device Authorization | POST | `/agentos-server/oauth2/device_authorization` |
| 换 Token / 刷新 / Device Code 轮询 | POST | `/agentos-server/oauth2/token` |
| 撤销 Token | POST | `/agentos-server/oauth2/revoke` |
| 登出 | GET | `/agentos-server/api/v1/auth/logout` |

### 默认 OAuth 客户端

| 配置项 | 默认值 |
|--------|--------|
| `client_id` | `agentos-desktop` |
| `redirect_uri`（仅 Redirect 流） | `http://127.0.0.1:53682/oauth/callback` |
| `scope`（Redirect 流默认带上） | `openid profile email phone agentos.read agentos.write` |
| `prompt`（Redirect 流） | `login`（每次授权要求重新认证） |
| Device Authorization 路径 | `/oauth2/device_authorization` |

可通过 `OAuthConfig` 覆盖 `clientId`、回调地址、scope、`deviceAuthorizationPath` 等。

### 后端需登记的 redirect 地址（仅 Redirect 流）

| 用途 | URL |
|------|-----|
| OAuth 登录回调 | `http://127.0.0.1:53682/oauth/callback` |

Device Code 流**不依赖**固定 `redirect_uri`，适合 Embedded / LAN。

登出接口建议请求头：`Authorization: Bearer <access_token>`。携带有效 token 时，服务端会撤销 access / refresh token 并清理授权记录；未携带或 token 无效时仍返回成功，但可能不会撤销已签发 token。

---

## 流程一：Authorization Code + PKCE（Desktop）

### 授权（浏览器）

```text
GET /agentos-server/oauth2/authorize
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
POST /agentos-server/oauth2/token
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

### Loopback 与浏览器成功页

默认全平台使用 **loopback + 本地 HTML**（`OAuthRedirectTransport.loopback`）。

```text
App                 Loopback :53682              Browser           AgentOS Server
 |                        |                        |                      |
 |-- start loopback ----->|                        |                      |
 |-- open authorize URL -------------------------->|                      |
 |                        |                        |-- /agentos-server/oauth2/authorize ->|
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

| 路径 | 说明 |
|------|------|
| `/oauth/callback` | OAuth `redirect_uri`，带 `code` / `state` |
| `/oauth/login/success` | 登录成功 HTML 页 |
| `/oauth/logout/success` | 登出成功 HTML 页 |

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

### 可选：自定义 Scheme 回调

SDK 保留 `OAuthRedirectTransport.customScheme` 与 `OAuthRedirectHandler`，可将 `redirect_uri` 设为 `agentos://oauth/callback`。当前 **默认未启用**，Desktop 使用 loopback。

成功页上的「返回 AgentOS」按钮会跳转 `agentos://open`，用于从浏览器手动唤起应用（需 Desktop 注册 `agentos://` scheme）。

---

## 流程二：Device Code（Embedded / LAN）

适用于无法使用固定 `redirect_uri` 的环境（例如设备通过局域网 IP 访问，地址会变）。

### Device Authorization

```text
POST /agentos-server/oauth2/device_authorization
Content-Type: application/x-www-form-urlencoded

client_id=agentos-desktop
# 默认不传 scope；需要时 AuthClient.beginDeviceCodeLogin(includeScope: true)
```

响应字段（节选）：`device_code`、`user_code`、`verification_uri`、`verification_uri_complete`、`expires_in`、`interval`。

### 轮询换 Token

```text
POST /agentos-server/oauth2/token
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:device_code
&client_id=agentos-desktop
&device_code={device_code}
```

常见错误码：`authorization_pending`、`slow_down`、`expired_token`。

### 使用示例

```dart
final client = AuthClient();
await client.initialize(serverAddress: serverAddress);

final session = await client.beginDeviceCodeLogin(
  serverAddress: serverAddress,
  config: const OAuthConfig(/* 可覆盖 clientId 等 */),
);

// 打开 session.verificationUriComplete（或 verificationUri + 展示 user_code）
await openUrl(session.verificationUriComplete);

var interval = Duration(seconds: session.interval);
while (!session.isExpired) {
  await Future<void>.delayed(interval);
  final result = await client.pollDeviceCode(session: session);

  switch (result.status) {
    case DeviceCodePollStatus.complete:
      print('登录成功: ${result.token!.accessToken}');
      return;
    case DeviceCodePollStatus.pending:
      if (result.slowDown) {
        interval += const Duration(seconds: 5); // 建议上限约 30s
      }
      break;
    case DeviceCodePollStatus.expired:
    case DeviceCodePollStatus.error:
      throw Exception(result.error ?? result.status.name);
  }
}
```

要点：

1. **默认不传 `scope`**；若认证中心要求显式 scope，设 `includeScope: true`
2. 轮询间隔以服务端返回的 `interval` 为准；收到 `slow_down` 时应加大间隔
3. 成功时 `pollDeviceCode` 会**自动持久化**会话（与 Redirect 流一致）
4. 若 SaaS 返回的 `verification_uri` 缺端口，由**应用层**按实际 `serverAddress` 改写后再打开浏览器（SDK 原样透传）

---

## 登出

```text
GET /agentos-server/api/v1/auth/logout
Authorization: Bearer <access_token>
```

响应示例：

```json
{
  "code": 200,
  "msg": "操作成功",
  "data": null
}
```

```dart
// 远端登出 + 清本地（推荐）
await client.logout();

// 仅清本地
await client.logoutLocal();
```

## 安装

```yaml
dependencies:
  agentos_auth: ^1.0.0
```

```bash
dart pub get
```

## 使用指南（共用）

### 本地调试（example）

在 `agentos-auth` 目录下运行。先修改 `example/example.dart` 顶部的 `_serverAddress` 常量。

```bash
cd agentos-auth
dart run example/example.dart
dart run example/example.dart logout
```

macOS / Linux / Windows 会尝试自动打开浏览器；失败则打印授权 URL。当前 example 演示的是 **Authorization Code + Loopback** 流。

### 刷新 Token

```dart
if (client.currentToken?.isExpired == true) {
  await client.refreshToken();
}
```

也可传入自定义 `OAuthConfig`（例如 Embedded 使用不同 `clientId`）：

```dart
await client.refreshToken(config: myConfig);
```

`AuthToken.isExpired` 在 `expiresAt` 前 60 秒即视为过期。

### 自定义存储

默认会把会话写入 JSON 文件（见下文“默认存储位置”），可通过 `storagePath` 修改文件位置；也可以传入自己的 `TokenStorage` 实现，例如仅保存在内存，或接入系统安全存储：

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
| `AuthClient` | OAuth 登录（Redirect / Device Code）、刷新、登出 |
| `OAuthConfig` / `OAuthDefaults` | 客户端 ID、回调地址、Device Authorization 路径等 |
| `DeviceCodeSession` / `DeviceCodePollResult` | Device Code 会话与轮询结果 |
| `LoopbackRedirectServer` | 本地 HTTP 服务 + HTML 成功页（Redirect 流） |
| `OAuthRedirectTransport` | 回调承载方式（默认 loopback） |
| `OAuthRedirectHandler` | 可选自定义 Scheme 回调注入 |
| `Pkce` | PKCE / state |
| `AuthSession` / `AuthToken` | 会话与 Token 模型 |
| `TokenStorage` | 持久化抽象 |

### 默认存储位置

- macOS / Linux：`~/.agentos/auth/session.json`
- Windows：`%USERPROFILE%\.agentos\auth\session.json` 或 `%APPDATA%\.agentos\auth\session.json`

## 注意事项

- 服务器地址由应用层配置，SDK 不做服务发现
- **选流**：Desktop / 固定回调用 Redirect；Embedded / LAN 用 Device Code，不要混用同一产品入口的两套 UI
- Redirect：端口 `53682` 被占用时登录失败，需释放或修改 `OAuthConfig.redirectPort` 并与后端登记一致
- Redirect：登录在收到 `/oauth/callback` 后即完成；应用不应在此时强制抢浏览器焦点，由用户在成功页自行返回
- Redirect：认证中心登录页须在成功后正确跳回 `/oauth2/authorize`（携带 `redirect` 参数），否则浏览器只显示网站内「登录成功」而 loopback 收不到 `code`
- Device Code：轮询需处理 `authorization_pending` / `slow_down` / `expired_token`；`scope` 默认省略
- 更高安全要求时，可通过 `TokenStorage` 接入系统安全存储
