import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../services/accuniq_service.dart';
import '../services/storage_service.dart';
import '../models/device_info.dart';
import '../models/member_info.dart';
import '../models/measurement_result.dart';

/// Provider for Accuniq device state management
class AccuniqProvider with ChangeNotifier {
  final AccuniqService _service = AccuniqService();
  StorageService? _storageService;
  bool _autoConnectEnabled = false;
  bool _isAutoConnecting = false;

  // State
  bool _isConnecting = false;
  bool _isScanning = false;
  dynamic _selectedDevice; // BluetoothDevice for HC-05-USB
  final List<String> _logs = [];
  MeasurementResult? _lastMeasurement;
  List<dynamic> _availableDevices = []; // Bluetooth Classic devices only

  // Getters
  AccuniqService get service => _service;
  bool get isConnected => _service.isConnected;
  bool get isConnecting => _isConnecting;
  bool get isScanning => _isScanning;
  bool get isAutoConnecting => _isAutoConnecting;
  bool get isAndroid => AccuniqService.isAndroid;
  DeviceInfo? get deviceInfo => _service.deviceInfo;
  DeviceState get currentState => _service.currentState;
  dynamic get selectedDevice => _selectedDevice;
  List<String> get logs => _logs;
  MeasurementResult? get lastMeasurement => _lastMeasurement;
  List<dynamic> get availableDevices => _availableDevices;
  bool get autoConnectEnabled => _autoConnectEnabled;

  AccuniqProvider() {
    _initializeStorage();
    _setupListeners();
    _loadInitialDevices();
  }

  /// Initialize storage service and load auto-connect preference
  Future<void> _initializeStorage() async {
    _storageService = await StorageService.getInstance();

    // Enable auto-connect by default if not set
    _autoConnectEnabled = _storageService!.isAutoConnectEnabled();
    if (!_autoConnectEnabled) {
      await _storageService!.setAutoConnectEnabled(true);
      _autoConnectEnabled = true;
      _logs.add('[Init] Auto-connect enabled by default');
    }

    // Note: HC-05-USB doesn't need preferred device setup
    // Users will pair HC-05 manually in Bluetooth settings

    notifyListeners();
  }

  // Auto-reconnect variables
  bool _isReconnecting = false;
  Timer? _reconnectTimer;

  // Auto-connect retry variables
  Timer? _autoConnectRetryTimer;
  int _autoConnectRetryCount = 0;
  static const int _maxAutoConnectRetries = 5;
  static const Duration _autoConnectRetryInterval = Duration(seconds: 12);

  void _setupListeners() {
    _service.deviceInfoStream.listen((info) {
      notifyListeners();
    });

    _service.stateStream.listen((state) {
      notifyListeners();
    });

    _service.measurementStream.listen((result) {
      _lastMeasurement = result;
      notifyListeners();
    });

    _service.logStream.listen((log) {
      _logs.add(log);
      if (_logs.length > 100) {
        _logs.removeAt(0);
      }
      notifyListeners();
    });

    // Listen to connection state changes for auto-reconnect
    _service.connectionStateStream.listen((isConnected) {
      if (isConnected) {
        _logs.add('[Connection] ✅ Connected to device');
        _autoConnectRetryCount =
            0; // Reset retry count on successful connection
        _autoConnectRetryTimer?.cancel();
      } else if (!isConnected &&
          _autoConnectEnabled &&
          !_service.wasManualDisconnect) {
        // Connection lost (not manual disconnect) - attempt auto-reconnect
        _logs.add(
          '[Connection] 🔴 Connection lost, scheduling auto-reconnect...',
        );
        _scheduleAutoReconnect();
      }
      notifyListeners();
    });
  }

  /// Schedule auto-reconnect after a delay
  void _scheduleAutoReconnect() {
    if (_isReconnecting) return; // Already reconnecting

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _attemptAutoReconnect();
    });
  }

  /// Attempt to auto-reconnect
  Future<void> _attemptAutoReconnect() async {
    if (_isReconnecting || isConnected || !_autoConnectEnabled) return;

    _isReconnecting = true;
    notifyListeners();

    try {
      await Future.delayed(const Duration(seconds: 1));
      await _attemptAutoConnect();
    } finally {
      _isReconnecting = false;
      notifyListeners();
    }
  }

  /// Load initial devices on startup
  Future<void> _loadInitialDevices() async {
    // Initialize storage if not already done
    if (_storageService == null) {
      await _initializeStorage();
    }

    if (isAndroid) {
      // Load devices first before attempting auto-connect
      await refreshBluetoothDevices();

      // Attempt auto-connect if enabled
      if (_autoConnectEnabled) {
        await _attemptAutoConnect();
      }
    }
  }

  /// Scan for Bluetooth Classic devices (Android) - HC-05-USB only
  Future<void> refreshBluetoothDevices() async {
    if (!isAndroid) return;

    _isScanning = true;
    notifyListeners();

    try {
      // Get Bluetooth Classic devices only (HC-05-USB)
      _availableDevices = await _service.getAvailableBluetoothDevices();
    } catch (e) {
      _logs.add('[ERROR] Failed to scan Bluetooth devices: $e');
    }

    _isScanning = false;
    notifyListeners();
  }

  /// Connect to device (Auto-detects Serial or Bluetooth)
  Future<bool> connect(dynamic device) async {
    _selectedDevice = device;
    _isConnecting = true;
    notifyListeners();

    bool success = await _service.connect(device);

    _isConnecting = false;
    notifyListeners();

    // Save device info on successful connection
    if (success && _storageService != null) {
      await _saveLastConnectedDevice(device);
    }

    return success;
  }

  /// Save last connected device information
  Future<void> _saveLastConnectedDevice(dynamic device) async {
    if (_storageService == null) return;

    if (device is BluetoothDevice) {
      // Bluetooth Classic device (HC-05-USB)
      await _storageService!.saveLastConnectedDevice(
        deviceId: device.address,
        deviceType: 'bluetooth',
        deviceName: device.name ?? 'HC-05-USB',
      );
    }
  }

  /// Attempt auto-connect based on priority
  Future<void> _attemptAutoConnect() async {
    if (_storageService == null) {
      await _initializeStorage();
    }

    if (!_autoConnectEnabled || isConnected) {
      _autoConnectRetryCount = 0; // Reset retry count if already connected
      return;
    }

    _isAutoConnecting = true;
    notifyListeners();

    _logs.add('[Auto-Connect] Starting auto-connect attempt...');

    try {
      // Priority 1: Try to connect to last connected device
      final lastDevice = _storageService!.getLastConnectedDevice();
      if (lastDevice != null) {
        _logs.add(
          '[Auto-Connect] Looking for last device: ${lastDevice['deviceName']} (${lastDevice['deviceId']})',
        );
        final device = await _findDeviceById(
          lastDevice['deviceId']!,
          lastDevice['deviceType']!,
        );
        if (device != null) {
          _logs.add(
            '[Auto-Connect] Found last device, attempting connection...',
          );
          final success = await connect(device);
          if (success) {
            _logs.add(
              '[Auto-Connect] ✅ Successfully connected to ${lastDevice['deviceName']}',
            );
            _storageService!.resetAutoConnectFailCount();
            _autoConnectRetryCount = 0; // Reset retry count on success
            _autoConnectRetryTimer?.cancel();
            _isAutoConnecting = false;
            notifyListeners();
            return;
          } else {
            _logs.add(
              '[Auto-Connect] ❌ Failed to connect to ${lastDevice['deviceName']}',
            );
            final failCount = await _storageService!
                .incrementAutoConnectFailCount();

            // Clear last device if failed 3 times
            if (failCount >= 3) {
              _logs.add(
                '[Auto-Connect] Clearing last device after 3 failed attempts',
              );
              await _storageService!.clearLastConnectedDevice();
            }
          }
        } else {
          _logs.add('[Auto-Connect] Last device not found in paired devices');
        }
      }

      // Priority 2: Try first HC-05 device (Android only)
      if (isAndroid) {
        _logs.add('[Auto-Connect] Searching for HC-05-USB devices...');
        final hc05Devices = await _service.findHC05Devices();
        if (hc05Devices.isNotEmpty) {
          _logs.add(
            '[Auto-Connect] Found ${hc05Devices.length} HC-05-USB device(s), attempting connection...',
          );
          final success = await connect(hc05Devices.first);
          if (success) {
            _logs.add('[Auto-Connect] ✅ Successfully connected to HC-05-USB');
            _autoConnectRetryCount = 0; // Reset retry count on success
            _autoConnectRetryTimer?.cancel();
            _isAutoConnecting = false;
            notifyListeners();
            return;
          } else {
            _logs.add('[Auto-Connect] ❌ Failed to connect to HC-05-USB');
          }
        } else {
          _logs.add(
            '[Auto-Connect] No HC-05-USB devices found in paired devices',
          );
        }
      }

      // Auto-connect failed - schedule retry if not exceeded max retries
      _logs.add('[Auto-Connect] No suitable device found or connection failed');
      if (_autoConnectRetryCount < _maxAutoConnectRetries) {
        _scheduleAutoConnectRetry();
      } else {
        _logs.add(
          '[Auto-Connect] Max retries ($_maxAutoConnectRetries) reached. Stopping auto-connect.',
        );
        _autoConnectRetryCount = 0; // Reset for next time
      }
    } catch (e) {
      _logs.add('[Auto-Connect] ❌ Error: $e');
      if (_autoConnectRetryCount < _maxAutoConnectRetries) {
        _scheduleAutoConnectRetry();
      }
    } finally {
      _isAutoConnecting = false;
      notifyListeners();
    }
  }

  /// Schedule auto-connect retry after delay
  void _scheduleAutoConnectRetry() {
    _autoConnectRetryTimer?.cancel();
    _autoConnectRetryCount++;

    _logs.add(
      '[Auto-Connect] Scheduling retry $_autoConnectRetryCount/$_maxAutoConnectRetries in ${_autoConnectRetryInterval.inSeconds} seconds...',
    );

    _autoConnectRetryTimer = Timer(_autoConnectRetryInterval, () {
      if (!isConnected && _autoConnectEnabled) {
        _attemptAutoConnect();
      }
    });
  }

  /// Find device by ID in available devices list
  Future<dynamic> _findDeviceById(String deviceId, String deviceType) async {
    if (deviceType == 'bluetooth') {
      // Refresh Bluetooth devices if needed
      if (_availableDevices.isEmpty && isAndroid) {
        await refreshBluetoothDevices();
      }

      // Find device by address (Bluetooth Classic only)
      for (var device in _availableDevices) {
        if (device is BluetoothDevice && device.address == deviceId) {
          return device;
        }
      }
    }

    return null;
  }

  /// Set auto-connect enabled/disabled
  Future<void> setAutoConnectEnabled(bool enabled) async {
    if (_storageService == null) {
      await _initializeStorage();
    }

    _autoConnectEnabled = enabled;
    await _storageService!.setAutoConnectEnabled(enabled);
    notifyListeners();

    if (enabled && !isConnected) {
      // Attempt auto-connect immediately if enabled
      await _attemptAutoConnect();
    }
  }

  /// Disconnect from device
  void disconnect() {
    // Cancel any pending reconnect and retry
    _reconnectTimer?.cancel();
    _autoConnectRetryTimer?.cancel();
    _isReconnecting = false;
    _autoConnectRetryCount = 0;
    // Mark as manual disconnect
    _service.disconnect(isManual: true);
    _selectedDevice = null;
    _lastMeasurement = null;
    _logs.add('[Disconnect] Manually disconnected from device');
    notifyListeners();
  }

  /// Send member information
  Future<bool> sendMemberInfo(MemberInfo member) async {
    return await _service.sendMemberInfo(member);
  }

  /// Request measurement
  void requestMeasurement() {
    _service.requestMeasurement();
  }

  /// Sync time
  void syncTime() {
    _service.syncTime();
  }

  /// Clear logs
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _autoConnectRetryTimer?.cancel();
    _service.dispose();
    super.dispose();
  }
}
