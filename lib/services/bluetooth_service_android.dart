import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

// TimeoutException is part of dart:async, no need to import separately

/// Android Bluetooth Service for HC-05 Communication
class BluetoothServiceAndroid {
  BluetoothConnection? _connection;
  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;

  bool _isConnected = false;
  BluetoothDevice? _connectedDevice;

  // Stream controllers
  final _dataController = StreamController<Uint8List>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  // Getters
  bool get isConnected => _isConnected;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  Stream<Uint8List> get dataStream => _dataController.stream;
  Stream<String> get errorStream => _errorController.stream;

  /// Check if Bluetooth is enabled
  Future<bool> isBluetoothEnabled() async {
    try {
      return await _bluetooth.isEnabled ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Request to enable Bluetooth
  Future<bool> requestEnable() async {
    try {
      return await _bluetooth.requestEnable() ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Request Bluetooth permissions
  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  /// Scan for Bluetooth devices (Bluetooth Classic only, BLE filtered out)
  Future<List<BluetoothDevice>> scanDevices() async {
    try {
      // Check permissions
      final hasPermissions = await requestPermissions();
      if (!hasPermissions) {
        _errorController.add('Bluetooth permissions not granted');
        return [];
      }

      // Check if Bluetooth is enabled
      final isEnabled = await isBluetoothEnabled();
      if (!isEnabled) {
        final enabled = await requestEnable();
        if (!enabled) {
          _errorController.add('Bluetooth is not enabled');
          return [];
        }
      }

      // Get bonded (paired) devices
      final List<BluetoothDevice> allDevices = await _bluetooth.getBondedDevices();
      
      // Filter out BLE devices - only return Bluetooth Classic devices
      final classicDevices = allDevices.where((device) => device.type != BluetoothDeviceType.le).toList();
      
      return classicDevices;
    } catch (e) {
      _errorController.add('Error scanning devices: $e');
      return [];
    }
  }

  /// Get paired devices only (Bluetooth Classic only, BLE filtered out)
  Future<List<BluetoothDevice>> getPairedDevices() async {
    try {
      final allDevices = await _bluetooth.getBondedDevices();
      // Filter out BLE devices - only return Bluetooth Classic devices
      return allDevices.where((device) => device.type != BluetoothDeviceType.le).toList();
    } catch (e) {
      _errorController.add('Error getting paired devices: $e');
      return [];
    }
  }

  /// Get all paired devices including BLE (for debugging/info)
  Future<List<BluetoothDevice>> getAllPairedDevices() async {
    try {
      return await _bluetooth.getBondedDevices();
    } catch (e) {
      _errorController.add('Error getting paired devices: $e');
      return [];
    }
  }

  /// Connect to a Bluetooth device with retry logic
  Future<bool> connect(BluetoothDevice device, {int maxRetries = 3}) async {
    // Check device type - BLE devices are not supported
    if (device.type == BluetoothDeviceType.le) {
      final errorMsg = '❌ Bluetooth Low Energy (BLE) devices are not supported.\n\n'
          'This app only supports Bluetooth Classic (SPP) devices.\n\n'
          'Device "${device.name ?? device.address}" is a BLE device.\n\n'
          '💡 Solution:\n'
          '• Use a Bluetooth Classic adapter like HC-05 module\n'
          '• Or use a different device that supports Bluetooth Classic';
      _errorController.add(errorMsg);
      return false;
    }

    // Check if device is bonded/paired
    if (!device.isBonded) {
      final errorMsg = '⚠️  Device is not paired. Please pair "${device.name ?? device.address}" in Bluetooth settings first.';
      _errorController.add(errorMsg);
      _errorController.add('💡 Go to: Settings → Bluetooth → Pair "${device.name ?? device.address}"');
      return false;
    }

    // Close existing connection if any
    await disconnect();

    // Wait a bit before connecting to ensure previous connection is fully closed
    await Future.delayed(const Duration(milliseconds: 500));

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // Attempt connection with timeout
        _connection = await BluetoothConnection.toAddress(device.address)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw TimeoutException('Connection timeout', const Duration(seconds: 10));
              },
            );

        if (_connection != null && _connection!.isConnected) {
          _isConnected = true;
          _connectedDevice = device;

          // Start listening to data (silent - only pass data)
          _connection!.input!.listen(
            (Uint8List data) {
              _dataController.add(data);
            },
            onDone: () {
              _isConnected = false;
              _errorController.add('🔴 Connection closed');
            },
            onError: (error) {
              _errorController.add('❌ Connection error: $error');
              disconnect();
            },
          );

          // Log connection success
          final deviceName = device.name ?? device.address;
          print('✅ Connected to $deviceName');
          _errorController.add('✅ Connected successfully to $deviceName');
          return true;
        }
      } catch (e) {
        _errorController.add('❌ Attempt $attempt failed: ${e.toString()}');
        
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: 1000 * attempt); // Exponential backoff
          await Future.delayed(delay);
        } else {
          _errorController.add('❌ Connection failed after $maxRetries attempts: $e');
        }
      }
    }

    return false;
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    try {
      await _connection?.close();
      _connection?.dispose();
      _connection = null;
      _isConnected = false;
      _connectedDevice = null;
      _errorController.add('Disconnected');
    } catch (e) {
      _errorController.add('Disconnect error: $e');
    }
  }

  /// Send data to device
  Future<bool> sendData(Uint8List data) async {
    if (!_isConnected || _connection == null) {
      _errorController.add('Not connected');
      return false;
    }

    try {
      _connection!.output.add(data);
      await _connection!.output.allSent;
      return true;
    } catch (e) {
      _errorController.add('Send error: $e');
      return false;
    }
  }

  /// Check if a device is likely an HC-05 module
  static bool isLikelyHC05(BluetoothDevice device) {
    final name = device.name?.toLowerCase() ?? '';
    return name.contains('hc-05') ||
        name.contains('hc05') ||
        name.contains('accuniq') ||
        name.startsWith('hc');
  }

  /// Find HC-05 devices from paired devices
  Future<List<BluetoothDevice>> findHC05Devices() async {
    final devices = await getPairedDevices();
    return devices.where((device) => isLikelyHC05(device)).toList();
  }

  /// Find device by name in paired devices
  Future<BluetoothDevice?> findDeviceByName(String deviceName) async {
    final devices = await getPairedDevices();
    final lowerName = deviceName.toLowerCase();
    
    for (var device in devices) {
      final name = device.name?.toLowerCase() ?? '';
      if (name == lowerName || name.contains(lowerName) || lowerName.contains(name)) {
        return device;
      }
    }
    
    return null;
  }

  /// Find device by MAC address in paired devices
  Future<BluetoothDevice?> findDeviceByAddress(String address) async {
    final devices = await getPairedDevices();
    final lowerAddress = address.toLowerCase().replaceAll(':', '').replaceAll('-', '');
    
    for (var device in devices) {
      final deviceAddress = device.address.toLowerCase().replaceAll(':', '').replaceAll('-', '');
      if (deviceAddress == lowerAddress) {
        return device;
      }
    }
    
    return null;
  }

  /// Find device by name or address (checks paired devices first)
  Future<BluetoothDevice?> findDeviceByNameOrAddress({
    String? name,
    String? address,
  }) async {
    // Try by address first (more reliable)
    if (address != null) {
      final deviceByAddress = await findDeviceByAddress(address);
      if (deviceByAddress != null) return deviceByAddress;
    }
    
    // Try by name
    if (name != null) {
      final deviceByName = await findDeviceByName(name);
      if (deviceByName != null) return deviceByName;
    }
    
    return null;
  }

  /// Scan for nearby devices and find by name or address
  /// Note: This requires additional permissions and may take longer
  Future<BluetoothDevice?> scanAndFindDevice({
    String? name,
    String? address,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      // Check permissions
      final hasPermissions = await requestPermissions();
      if (!hasPermissions) {
        print('⚠️ [BT] No permissions for scanning');
        return null;
      }

      // Check if Bluetooth is enabled
      final isEnabled = await isBluetoothEnabled();
      if (!isEnabled) {
        final enabled = await requestEnable();
        if (!enabled) {
          print('⚠️ [BT] Bluetooth not enabled');
          return null;
        }
      }

      print('🔍 [BT] Starting scan for device: ${name ?? address}...');

      // Try to find in paired devices first (faster)
      final pairedDevice = await findDeviceByNameOrAddress(name: name, address: address);
      if (pairedDevice != null) {
        print('✅ [BT] Found device in paired list');
        return pairedDevice;
      }

      // Note: flutter_bluetooth_serial doesn't support active scanning easily
      // The device must be paired first. We return null here and let the caller
      // handle pairing guidance to the user.
      print('⚠️ [BT] Device not found in paired devices. Please pair manually first.');
      return null;
    } catch (e) {
      print('❌ [BT] Error scanning for device: $e');
      return null;
    }
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _dataController.close();
    _errorController.close();
  }
}

/// Helper class for device info
class BluetoothDeviceInfo {
  final String name;
  final String address;
  final bool isBonded;
  final bool isConnected;

  BluetoothDeviceInfo({
    required this.name,
    required this.address,
    required this.isBonded,
    required this.isConnected,
  });

  factory BluetoothDeviceInfo.fromDevice(BluetoothDevice device) {
    return BluetoothDeviceInfo(
      name: device.name ?? 'Unknown',
      address: device.address,
      isBonded: device.isBonded,
      isConnected: device.isConnected,
    );
  }

  @override
  String toString() {
    return '$name ($address)${isBonded ? ' [Paired]' : ''}';
  }
}

