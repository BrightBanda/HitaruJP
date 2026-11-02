import 'dart:async';

import 'package:ingrain/features/notifications/data/push_gateway.dart';

/// A phone with scriptable push permission and token, and no Firebase.
class FakePushGateway implements PushGateway {
  FakePushGateway({
    this.supported = true,
    this.permitted = false,
    this.willGrant = true,
    this.currentToken = 'fcm-token-1',
    this.launch,
  });

  final bool supported;
  bool permitted;

  /// What the system answers when asked for permission.
  bool willGrant;
  String? currentToken;
  String? launch;

  int permissionRequests = 0;
  int starts = 0;
  bool tokenDeleted = false;

  final _refreshes = StreamController<String>.broadcast();
  final _taps = StreamController<String>.broadcast();

  void refreshToken(String token) {
    currentToken = token;
    _refreshes.add(token);
  }

  void tap(String route) => _taps.add(route);

  @override
  bool get isSupported => supported;

  @override
  Future<void> start() async => starts++;

  @override
  Future<bool> isPermitted() async => permitted;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    permitted = willGrant;
    return permitted;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Stream<String> get tokenRefreshes => _refreshes.stream;

  @override
  Stream<String> get routesOpened => _taps.stream;

  @override
  Future<String?> launchRoute() async => launch;

  @override
  Future<void> deleteToken() async => tokenDeleted = true;
}
