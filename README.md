# agentos-auth

AgentOS 用户认证 SDK，提供登录、刷新 Token、登出等功能。

## 功能特性

- **登录认证**：邮箱 + 密码登录
- **Token 管理**：内存缓存 + 可配置持久化存储
- **自动初始化**：从本地存储恢复登录状态
- **刷新 Token**：基于旧 Token 换取新 Token
- **登出**：清除 Token 和认证状态

## 接口规范

网关前缀由 SDK 固定处理为 `/liteAgent`，开发者只需要配置纯服务器地址，例如：

```text
https://liteagent-gray.liteagent.cn
```

最终请求路径形如：

- 登录：`POST https://host:port/liteAgent/v1/agentOS/login`
- 刷新：`POST https://host:port/liteAgent/v1/agentOS/refreshToken`
- 登出：`POST https://host:port/liteAgent/v1/agentOS/logout`

### 登录

- **方法**：`POST /liteAgent/v1/agentOS/login`
- **参数（Query）**：
  - `email`: string，用户邮箱
  - `password`: string，用户密码
- **响应**：

```json
{
  "code": 200,
  "message": "请求成功",
  "data": "token字符串"
}
```

### 刷新 Token

- **方法**：`POST /liteAgent/v1/agentOS/refreshToken`
- **Header**：
  - `Authorization: Bearer {旧 token}`
- **响应**：与登录相同，`data` 字段为新的 token 字符串

### 登出

- **方法**：`POST /liteAgent/v1/agentOS/logout`
- **Header**：
  - `Authorization: Bearer {当前 token}`
- **响应**：

```json
{
  "code": 200,
  "message": "请求成功",
  "data": ""
}
```

## 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  agentos_auth:
    path: ../agentos-auth
```

然后运行：

```bash
dart pub get
```

## 使用指南

### 推荐用法（默认持久化）

```dart
import 'package:agentos_auth/agentos_auth.dart';

void main() async {
  const serverAddress = 'https://liteagent-gray.liteagent.cn';

  // 默认使用 DefaultTokenStorage，Token 会保存到 ~/.agentos/auth/token.json
  final client = AuthClient();

  // 应用启动时先尝试从本地恢复登录状态
  await client.initialize(serverAddress: serverAddress);
  if (client.isAuthenticated) {
    print('已从存储恢复登录状态');
    print('Token: ${client.currentToken?.accessToken}');
    print('服务器地址: ${client.currentServerAddress}');
    return;
  }

  // 首次登录
  final response = await client.login(
    serverAddress: serverAddress,
    email: 'user@example.com',
    password: 'password123',
  );

  print('登录成功: ${response.token.accessToken}');

  // 刷新 Token
  final refresh = await client.refreshToken();
  print('刷新 Token 成功: ${refresh.token.accessToken}');

  // 登出
  await client.logout();
}
```

### 仅内存（不落盘）

```dart
final client = AuthClient(
  // 显式禁用持久化
  tokenStorage: null,
);

await client.login(
  serverAddress: serverAddress,
  email: 'user@example.com',
  password: 'password123',
);

// 进程结束后 Token 不会持久化
```

### 自定义存储实现

实现 `TokenStorage` 以接入数据库、加密存储等：

```dart
class MyTokenStorage implements TokenStorage {
  @override
  Future<void> saveToken(AuthToken token) async {
    // 保存逻辑
  }

  @override
  Future<AuthToken?> loadToken() async {
    // 读取逻辑
    return null;
  }

  @override
  Future<void> clearToken() async {
    // 清除逻辑
  }

  @override
  Future<bool> hasToken() async {
    // 检查是否有 token
    return false;
  }
}

final client = AuthClient(
  tokenStorage: MyTokenStorage(),
);
```

## 架构概览

- `AuthClient`：对外的认证客户端，封装登录 / 刷新 / 登出流程
- `ApiClient`：基于 Dio 的 HTTP 封装
- `AuthToken`：Token 模型，包含 `accessToken`、`tokenType`、`createdAt`
- `TokenStorage`：Token 存储抽象接口
- `DefaultTokenStorage`：默认基于文件的实现，使用混淆后的 JSON 存储

### 默认存储位置

`DefaultTokenStorage` 默认存储路径（非严格承诺，仅供理解）：

- macOS / Linux：`~/.agentos/auth/token.json`
- Windows：`%USERPROFILE%\.agentos\auth\token.json` 或 `%APPDATA%\.agentos\auth\token.json`

## 注意事项

- 当前不处理 Token 过期时间，`AuthToken.isExpired` 始终返回 `false`，过期策略由后端控制
- 服务器地址需要由开发者在应用层 hardcode，SDK 不做发现或切换
- 如需安全性更高的存储方式，可通过 `TokenStorage` 接口接入系统安全存储（Keychain / Keystore 等）
