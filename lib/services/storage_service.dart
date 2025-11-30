import 'package:shared_preferences/shared_preferences.dart';

/// Storage service for persisting device connection preferences
class StorageService {
  static const String _keyAutoConnectEnabled = 'auto_connect_enabled';
  static const String _keyLastDeviceId = 'last_device_id';
  static const String _keyLastDeviceType = 'last_device_type';
  static const String _keyLastDeviceName = 'last_device_name';
  static const String _keyLastConnectedTime = 'last_connected_time';
  static const String _keyAutoConnectFailCount = 'auto_connect_fail_count';
  static const String _keyPreferredDeviceId = 'preferred_device_id';
  static const String _keyPreferredDeviceName = 'preferred_device_name';
  static const String _keyPreferredDevicePin = 'preferred_device_pin';
  static const String _keyMockModeEnabled = 'mock_mode_enabled';

  static StorageService? _instance;
  SharedPreferences? _prefs;

  StorageService._();

  /// Get singleton instance
  static Future<StorageService> getInstance() async {
    _instance ??= StorageService._();
    _instance!._prefs ??= await SharedPreferences.getInstance();
    return _instance!;
  }

  /// Check if auto-connect is enabled
  bool isAutoConnectEnabled() {
    return _prefs?.getBool(_keyAutoConnectEnabled) ?? false;
  }

  /// Set auto-connect enabled/disabled
  Future<bool> setAutoConnectEnabled(bool enabled) async {
    return await _prefs?.setBool(_keyAutoConnectEnabled, enabled) ?? false;
  }

  /// Save last connected device information
  Future<bool> saveLastConnectedDevice({
    required String deviceId,
    required String deviceType,
    required String deviceName,
  }) async {
    final success1 = await _prefs?.setString(_keyLastDeviceId, deviceId) ?? false;
    final success2 = await _prefs?.setString(_keyLastDeviceType, deviceType) ?? false;
    final success3 = await _prefs?.setString(_keyLastDeviceName, deviceName) ?? false;
    final success4 = await _prefs?.setString(
      _keyLastConnectedTime,
      DateTime.now().toIso8601String(),
    ) ?? false;

    // Reset fail count on successful connection
    await _prefs?.remove(_keyAutoConnectFailCount);

    return success1 && success2 && success3 && success4;
  }

  /// Get last connected device information
  Map<String, String>? getLastConnectedDevice() {
    final deviceId = _prefs?.getString(_keyLastDeviceId);
    final deviceType = _prefs?.getString(_keyLastDeviceType);
    final deviceName = _prefs?.getString(_keyLastDeviceName);
    final lastConnected = _prefs?.getString(_keyLastConnectedTime);

    if (deviceId == null || deviceType == null) {
      return null;
    }

    return {
      'deviceId': deviceId,
      'deviceType': deviceType,
      'deviceName': deviceName ?? 'Unknown',
      'lastConnected': lastConnected ?? '',
    };
  }

  /// Clear last connected device information
  Future<bool> clearLastConnectedDevice() async {
    final success1 = await _prefs?.remove(_keyLastDeviceId) ?? false;
    final success2 = await _prefs?.remove(_keyLastDeviceType) ?? false;
    final success3 = await _prefs?.remove(_keyLastDeviceName) ?? false;
    final success4 = await _prefs?.remove(_keyLastConnectedTime) ?? false;
    final success5 = await _prefs?.remove(_keyAutoConnectFailCount) ?? false;

    return success1 && success2 && success3 && success4 && success5;
  }

  /// Increment auto-connect failure count
  Future<int> incrementAutoConnectFailCount() async {
    final currentCount = _prefs?.getInt(_keyAutoConnectFailCount) ?? 0;
    final newCount = currentCount + 1;
    await _prefs?.setInt(_keyAutoConnectFailCount, newCount);
    return newCount;
  }

  /// Get auto-connect failure count
  int getAutoConnectFailCount() {
    return _prefs?.getInt(_keyAutoConnectFailCount) ?? 0;
  }

  /// Reset auto-connect failure count
  Future<bool> resetAutoConnectFailCount() async {
    return await _prefs?.remove(_keyAutoConnectFailCount) ?? false;
  }

  /// Save preferred device information
  Future<bool> savePreferredDevice({
    required String deviceId,
    required String deviceName,
    String? pinCode,
  }) async {
    final success1 = await _prefs?.setString(_keyPreferredDeviceId, deviceId) ?? false;
    final success2 = await _prefs?.setString(_keyPreferredDeviceName, deviceName) ?? false;
    if (pinCode != null) {
      await _prefs?.setString(_keyPreferredDevicePin, pinCode);
    }
    return success1 && success2;
  }

  /// Get preferred device information
  Map<String, String>? getPreferredDevice() {
    final deviceId = _prefs?.getString(_keyPreferredDeviceId);
    final deviceName = _prefs?.getString(_keyPreferredDeviceName);
    final pinCode = _prefs?.getString(_keyPreferredDevicePin);

    if (deviceId == null || deviceName == null) {
      return null;
    }

    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'pinCode': pinCode ?? '',
    };
  }

  /// Clear preferred device information
  Future<bool> clearPreferredDevice() async {
    final success1 = await _prefs?.remove(_keyPreferredDeviceId) ?? false;
    final success2 = await _prefs?.remove(_keyPreferredDeviceName) ?? false;
    final success3 = await _prefs?.remove(_keyPreferredDevicePin) ?? false;
    return success1 && success2 && success3;
  }

  /// Check if mock mode is enabled
  bool isMockModeEnabled() {
    return _prefs?.getBool(_keyMockModeEnabled) ?? false;
  }

  /// Set mock mode enabled/disabled
  Future<bool> setMockModeEnabled(bool enabled) async {
    return await _prefs?.setBool(_keyMockModeEnabled, enabled) ?? false;
  }
}

