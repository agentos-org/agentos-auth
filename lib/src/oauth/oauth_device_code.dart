import 'oauth_config.dart';
import '../models/token.dart';

/// Device Code authorization session (RFC 8628)
class DeviceCodeSession {
  DeviceCodeSession({
    required this.serverAddress,
    required this.config,
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresIn,
    required this.interval,
    DateTime? expiresAt,
  }) : expiresAt = expiresAt ?? DateTime.now().add(Duration(seconds: expiresIn));

  final String serverAddress;
  final OAuthConfig config;
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final String verificationUriComplete;
  final int expiresIn;
  final int interval;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  DeviceCodeSession copyWith({
    String? verificationUri,
    String? verificationUriComplete,
  }) {
    return DeviceCodeSession(
      serverAddress: serverAddress,
      config: config,
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: verificationUri ?? this.verificationUri,
      verificationUriComplete:
          verificationUriComplete ?? this.verificationUriComplete,
      expiresIn: expiresIn,
      interval: interval,
      expiresAt: expiresAt,
    );
  }
}

/// Device Code polling result status
enum DeviceCodePollStatus {
  pending,
  complete,
  expired,
  error,
}

/// Device Code polling result
class DeviceCodePollResult {
  const DeviceCodePollResult._({
    required this.status,
    this.slowDown = false,
    this.error,
    this.token,
  });

  factory DeviceCodePollResult.pending({bool slowDown = false}) =>
      DeviceCodePollResult._(
        status: DeviceCodePollStatus.pending,
        slowDown: slowDown,
      );

  factory DeviceCodePollResult.complete(AuthToken token) =>
      DeviceCodePollResult._(
        status: DeviceCodePollStatus.complete,
        token: token,
      );

  factory DeviceCodePollResult.expired([String? error]) =>
      DeviceCodePollResult._(
        status: DeviceCodePollStatus.expired,
        error: error,
      );

  factory DeviceCodePollResult.error(String error) => DeviceCodePollResult._(
        status: DeviceCodePollStatus.error,
        error: error,
      );

  final DeviceCodePollStatus status;
  final bool slowDown;
  final String? error;
  final AuthToken? token;
}
