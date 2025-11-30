import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'bluetooth_service_android.dart';
import 'accuniq_protocol.dart';
import '../models/device_info.dart';
import '../models/member_info.dart';
import '../models/measurement_result.dart';

/// Accuniq Device Communication Service
/// Supports Bluetooth Classic (HC-05-USB) for Android
class AccuniqService {
  // Bluetooth Classic (Android) - HC-05-USB
  BluetoothServiceAndroid? _bluetoothService;

  // Stream subscriptions
  StreamSubscription<Uint8List>? _btDataSubscription;
  StreamSubscription<String>? _btErrorSubscription;

  final PacketParser _parser = PacketParser();

  bool _isConnected = false;
  DeviceInfo? _deviceInfo;
  DeviceState _currentState = DeviceState.unknown;

  // Connection mode (only Bluetooth Classic for HC-05-USB)
  ConnectionMode _connectionMode = ConnectionMode.none;

  // Track last sent packet to filter out echo
  Uint8List? _lastSentPacket;

  // Track if disconnect was manual (user-initiated) or automatic (connection lost)
  bool _isManualDisconnect = false;

  // Stream controllers
  final _deviceInfoController = StreamController<DeviceInfo>.broadcast();
  final _stateController = StreamController<DeviceState>.broadcast();
  final _measurementController =
      StreamController<MeasurementResult>.broadcast();
  final _logController = StreamController<String>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  // Getters
  bool get isConnected => _isConnected;
  DeviceInfo? get deviceInfo => _deviceInfo;
  DeviceState get currentState => _currentState;
  ConnectionMode get connectionMode => _connectionMode;

  Stream<DeviceInfo> get deviceInfoStream => _deviceInfoController.stream;
  Stream<DeviceState> get stateStream => _stateController.stream;
  Stream<MeasurementResult> get measurementStream =>
      _measurementController.stream;
  Stream<String> get logStream => _logController.stream;
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  /// Check if running on Android
  static bool get isAndroid {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (e) {
      return false;
    }
  }

  /// Get available Bluetooth Classic devices (Android) - HC-05-USB only
  Future<List<dynamic>> getAvailableBluetoothDevices() async {
    if (!isAndroid) return [];

    _bluetoothService ??= BluetoothServiceAndroid();
    return await _bluetoothService!.scanDevices();
  }

  /// Find HC-05 devices from paired devices (Android)
  Future<List<dynamic>> findHC05Devices() async {
    if (!isAndroid) return [];

    _bluetoothService ??= BluetoothServiceAndroid();
    return await _bluetoothService!.findHC05Devices();
  }

  /// Find device by name or address (Android) - Bluetooth Classic only
  Future<dynamic> findDeviceByNameOrAddress({
    String? name,
    String? address,
  }) async {
    if (!isAndroid) return null;

    _bluetoothService ??= BluetoothServiceAndroid();
    return await _bluetoothService!.findDeviceByNameOrAddress(
      name: name,
      address: address,
    );
  }

  /// Connect to device via Bluetooth Classic (Android)
  Future<bool> connectBluetooth(dynamic device) async {
    try {
      _bluetoothService ??= BluetoothServiceAndroid();

      // Cancel existing subscriptions if any
      await _btDataSubscription?.cancel();
      await _btErrorSubscription?.cancel();

      // Listen to Bluetooth data (silent - only log actual data)
      _btDataSubscription = _bluetoothService!.dataStream.listen(
        (data) {
          _onDataReceived(data);
        },
        onError: (error) {
          _log('BT data error: $error');
        },
      );

      // Listen to Bluetooth errors (only log to UI)
      _btErrorSubscription = _bluetoothService!.errorStream.listen((error) {
        _log('BT: $error');

        // Detect connection closed/error and emit connection state for auto-reconnect
        if (error.contains('Connection closed') ||
            error.contains('Connection error') ||
            error.contains('Disconnected')) {
          // Connection was lost, not manual disconnect
          if (_isConnected) {
            disconnect(isManual: false);
          }
        }
      });

      final success = await _bluetoothService!.connect(device);

      if (!success) {
        return false;
      }

      _connectionMode = ConnectionMode.bluetooth;
      final initSuccess = await _initializeDevice();

      if (initSuccess) {
        final deviceName = device.name ?? device.address;
        print('✅ Connected and ready - waiting for data from $deviceName');
      }

      return initSuccess;
    } catch (e) {
      _log('BT connection error: $e');
      disconnect();
      return false;
    }
  }

  /// Connect to device via Bluetooth Classic (Android) - HC-05-USB
  Future<bool> connect(dynamic device) async {
    if (!isAndroid) {
      _log('Bluetooth Classic only available on Android');
      return false;
    }

    return await connectBluetooth(device);
  }

  /// Initialize device after connection
  /// For Scale-6E16: Device auto-sends data every 30s, no need to send requests
  Future<bool> _initializeDevice() async {
    // Don't send any requests - just wait for device to auto-send data
    // Device will automatically send measurement data every 30 seconds
    _isConnected = true;
    _isManualDisconnect = false;
    // Emit connection state
    _connectionStateController.add(true);
    // Do NOT start polling - device sends data automatically
    // Do NOT send any requests - just enable notifications
    _log('✅ Connected - waiting for auto data (device sends every 30s)');
    return true;
  }

  /// Check if received packet is an echo of the last sent packet
  bool _isEcho(List<int> receivedPacket, Uint8List lastSentPacket) {
    if (receivedPacket.length != lastSentPacket.length) {
      return false;
    }
    for (int i = 0; i < receivedPacket.length; i++) {
      if (receivedPacket[i] != lastSentPacket[i]) {
        return false;
      }
    }
    return true;
  }

  /// Disconnect from device
  /// [isManual] - true if user manually disconnected, false if connection lost
  void disconnect({bool isManual = true}) {
    _isManualDisconnect = isManual;
    _isConnected = false;
    _deviceInfo = null;
    _currentState = DeviceState.unknown;

    // Bluetooth Classic cleanup
    _bluetoothService?.disconnect();

    _connectionMode = ConnectionMode.none;
    // Emit connection state
    _connectionStateController.add(false);
    _log('Disconnected');
  }

  /// Check if last disconnect was manual
  bool get wasManualDisconnect => _isManualDisconnect;

  /// Send member information
  Future<bool> sendMemberInfo(MemberInfo member) async {
    if (!_isConnected) return false;

    try {
      final memberData = member.toDataString();
      _sendPacket(AccuniqProtocol.transmitMemberInfo(memberData));
      _log('Sent: Member Info - ${member.name}');

      // Wait for ACK
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (e) {
      _log('Error sending member info: $e');
      return false;
    }
  }

  /// Request measurement result
  void requestMeasurement() {
    if (!_isConnected) return;
    _sendPacket(AccuniqProtocol.requestMeasurementResult());
    _log('Sent: Request Measurement');
  }

  /// Sync time with device
  void syncTime() {
    if (!_isConnected) return;
    _sendPacket(AccuniqProtocol.transmitTime(DateTime.now()));
    _log('Sent: Sync Time');
  }

  // Private methods

  void _sendPacket(Uint8List packet) {
    try {
      // Store last sent packet to filter out echo
      _lastSentPacket = Uint8List.fromList(packet);

      if (_connectionMode == ConnectionMode.bluetooth) {
        if (_bluetoothService == null || !_bluetoothService!.isConnected)
          return;
        _bluetoothService!.sendData(packet);
      }
    } catch (e) {
      _log('Send error: $e');
    }
  }

  void _onDataReceived(Uint8List data) {
    // Log ALL received data - important for debugging
    _log('📥 [DATA] Received ${data.length} bytes');
    print('📥 [DATA] Received ${data.length} bytes');

    // Log HEX format
    final hexString = _bytesToHex(data);
    _log('📥 [DATA] HEX: $hexString');
    print('📥 [DATA] HEX: $hexString');

    // Try to log as ASCII if printable
    try {
      final asciiString = String.fromCharCodes(data);
      if (asciiString.codeUnits.every(
        (c) => c >= 32 && c <= 126 || c == 9 || c == 10 || c == 13,
      )) {
        _log('📥 [DATA] ASCII: $asciiString');
        print('📥 [DATA] ASCII: $asciiString');
      }
    } catch (e) {
      // Not ASCII, skip
    }

    for (var byte in data) {
      final packet = _parser.parseByte(byte);
      if (packet != null) {
        final packetHex = _bytesToHex(packet);
        _log('📦 [DATA] Parsed packet: $packetHex');
        print('📦 [DATA] Parsed packet: $packetHex');

        // Check if this is an echo of the last sent packet
        if (_lastSentPacket != null && _isEcho(packet, _lastSentPacket!)) {
          _log('⚠️  [DATA] Ignoring echo packet');
          print('⚠️  [DATA] Ignoring echo packet');
          continue; // Skip echo packets
        }
        _handlePacket(packet);
      }
    }
  }

  String _bytesToHex(List<int> bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  void _handlePacket(List<int> packet) {
    final command = PacketParser.getCommand(packet);
    final data = PacketParser.getData(packet);

    if (command == null) {
      // Silently ignore invalid packets
      return;
    }

    switch (command) {
      case 'I': // Device Version
        _log('📥 [CMD-I] Device Version received');
        if (data != null) {
          try {
            _deviceInfo = DeviceInfo.fromString(data);
            _deviceInfoController.add(_deviceInfo!);
            _log('✅ Device connected: ${_deviceInfo!.deviceName}');
            _log('📥 [CMD-I] Data: $data');
          } catch (e) {
            _log('❌ [CMD-I] Error parsing device info: $e');
          }
        }
        break;

      case 'K': // Serial Number
        _log('📥 [CMD-K] Serial Number received');
        if (data != null && _deviceInfo != null) {
          _deviceInfo = _deviceInfo!.copyWith(serialNumber: data);
          _deviceInfoController.add(_deviceInfo!);
          _log('📥 [CMD-K] Serial Number: $data');
        }
        break;

      case 'A': // Device State
        _log('📥 [CMD-A] Device State received');
        if (packet.length >= 3) {
          final stateByte = packet[2];
          final newState = DeviceStateExtension.fromByte(stateByte);
          _log(
            '📥 [CMD-A] State byte: 0x${stateByte.toRadixString(16).toUpperCase()}, State: ${newState.displayName}',
          );

          if (newState != _currentState) {
            _currentState = newState;
            _stateController.add(_currentState);
            _log('📥 [CMD-A] State changed to: ${newState.displayName}');

            // Auto request measurement when complete
            if (_currentState == DeviceState.completeDisplay) {
              Future.delayed(const Duration(milliseconds: 500), () {
                requestMeasurement();
              });
            }
          }
        }
        break;

      case 'M': // Measurement Result
        // This is the automatic measurement data sent every 30 seconds
        print('');
        print('═══════════════════════════════════════════════════════');
        print('📊 [DATA] MEASUREMENT DATA RECEIVED (Auto-sent by device)');
        print('═══════════════════════════════════════════════════════');

        // Parse measurement data
        try {
          // Extract data string
          if (data != null) {
            print('📊 [DATA] Raw CSV Data: $data');
            _log('📊 Received measurement data: $data');

            // Show CSV structure
            if (data.contains(',')) {
              final fields = data.split(',');
              print('📊 [DATA] Total CSV Fields: ${fields.length}');

              // Log all fields
              print('📊 [DATA] All CSV Fields:');
              for (int i = 0; i < fields.length; i++) {
                if (fields[i].isNotEmpty) {
                  print('  [$i] = "${fields[i]}"');
                }
              }
            }
          }

          final result = MeasurementResult.fromData(packet);
          _measurementController.add(result);

          print('✅ [DATA] ========== PARSED MEASUREMENT RESULTS ==========');
          print('✅ [DATA] Gender: ${result.gender}');
          print('✅ [DATA] Age: ${result.age} years');
          print('✅ [DATA] Height: ${result.height.toStringAsFixed(1)} cm');
          print('✅ [DATA] Weight: ${result.weight.toStringAsFixed(1)} kg');
          print('✅ [DATA] BMI: ${result.bmi.toStringAsFixed(1)}');
          print(
            '✅ [DATA] Body Fat %: ${result.bodyFatPercent.toStringAsFixed(1)}%',
          );
          print(
            '✅ [DATA] Body Fat Mass: ${result.bodyFatMass.toStringAsFixed(2)} kg',
          );
          print(
            '✅ [DATA] Skeletal Muscle Mass: ${result.skeletalMuscleMass.toStringAsFixed(1)} kg',
          );
          print(
            '✅ [DATA] Soft Lean Mass: ${result.softLeanMass.toStringAsFixed(1)} kg',
          );
          print(
            '✅ [DATA] Body Water: ${result.bodyWater.toStringAsFixed(1)} kg',
          );
          print('✅ [DATA] BMR: ${result.bmr.toStringAsFixed(0)} kcal');
          print(
            '✅ [Measurement] Body Cell Mass: ${result.bodyCellMass.toStringAsFixed(1)} kg',
          );
          print(
            '✅ [Measurement] Biological Age: ${result.biologicalAge} years',
          );
          print('✅ [Measurement] Body Type: ${result.bodyType}');
          print('✅ [Measurement] ====================================');
        } catch (e) {
          _log('❌ Error parsing measurement: $e');
          print('❌ [Measurement] Parse Error: $e');
          print('❌ [Measurement] Stack trace: ${StackTrace.current}');
        }
        break;

      case 'B': // Member Info ACK/NAK
        _log('📥 [CMD-B] Member Info ACK/NAK received');
        if (data != null) {
          _log('📥 [CMD-B] Data: $data');
        }
        break;

      default:
        // Log unknown commands
        if (data != null && data.isNotEmpty) {
          _log('⚠️  [DATA] Unknown command "$command" with data: $data');
          print('⚠️  [DATA] Unknown command "$command" with data: $data');
        } else {
          _log('⚠️  [DATA] Unknown command "$command" (no data)');
          print('⚠️  [DATA] Unknown command "$command" (no data)');
        }
    }
  }

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 23);
    _logController.add('[$timestamp] $message');
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _bluetoothService?.dispose();
    _deviceInfoController.close();
    _stateController.close();
    _measurementController.close();
    _logController.close();
    _connectionStateController.close();
  }
}

/// Connection mode enum
enum ConnectionMode {
  none,
  bluetooth, // Bluetooth Classic (HC-05-USB)
}
