// 示例：登录和登出接口使用
import 'package:agentos_auth/agentos_auth.dart';

void main() async {
  // 示例服务器地址（实际项目中请替换为自己的后端地址）
  const serverAddress = 'https://api.example.com';

  final client = AuthClient();
  await client.initialize(serverAddress: serverAddress);

  // 检查是否已恢复登录状态
  if (client.isAuthenticated) {
    print('已从存储恢复登录状态');
    print('Token: ${client.currentToken?.accessToken}');
    print('服务器地址: ${client.currentServerAddress}');
    return;
  }

  // 登录（服务器地址作为参数传入）
  try {
    final response = await client.login(
      serverAddress: serverAddress,
      email: 'user@example.com',
      password: 'password123',
    );

    print('登录成功！');
    print('Token: ${response.token.accessToken}');
    print('Token 类型: ${response.token.tokenType}');
    print('创建时间: ${response.token.createdAt}');
    print('服务器地址: ${client.currentServerAddress}');
    print('Token 已自动保存到默认路径');

    // 检查认证状态
    if (client.isAuthenticated) {
      print('已认证');
      print('当前 Token: ${client.currentToken?.accessToken}');
    }

    // 刷新 Token
    print('\n准备刷新 Token...');
    await Future.delayed(const Duration(seconds: 1));
    
    try {
      final refreshResponse = await client.refreshToken();
      print('刷新 Token 成功！');
      print('新 Token: ${refreshResponse.token.accessToken}');
    } catch (e) {
      print('刷新 Token 失败: $e');
    }

    // 等待一下，然后登出
    print('\n准备登出...');
    await Future.delayed(const Duration(seconds: 1));
    
    await client.logout();
    print('登出成功！');
    print('Token 已从存储中清除');
    
    // 验证登出后状态
    if (!client.isAuthenticated) {
      print('认证状态已清除');
      print('当前 Token: ${client.currentToken}');
      print('服务器地址: ${client.currentServerAddress}');
    }
  } catch (e) {
    print('操作失败: $e');
  }
}
