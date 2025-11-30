import 'dart:convert';
import 'dart:typed_data';

/// Accuniq Protocol Implementation
/// Based on RS-232 Serial Communication Protocol
/// Format: STX + COMMAND + DATA + ETX + BCC
class AccuniqProtocol {
  static const int STX = 0x02; // Start of Text
  static const int ETX = 0x03; // End of Text

  /// Create a packet with checksum
  static Uint8List createPacket(String command, [Uint8List? data]) {
    final List<int> packet = [];

    // Add STX
    packet.add(STX);

    // Add command
    packet.addAll(utf8.encode(command));

    // Add data if provided
    if (data != null && data.isNotEmpty) {
      packet.addAll(data);
    }

    // Add ETX
    packet.add(ETX);

    // Calculate and add checksum (BCC)
    final checksum = calculateChecksum(packet);
    packet.add(checksum);

    return Uint8List.fromList(packet);
  }

  /// Calculate checksum (sum of all bytes & 0xFF)
  static int calculateChecksum(List<int> data) {
    int sum = 0;
    for (var byte in data) {
      sum += byte;
    }
    return sum & 0xFF;
  }

  /// Verify checksum of received packet
  static bool verifyChecksum(List<int> packet) {
    if (packet.length < 4) return false;

    final dataWithoutChecksum = packet.sublist(0, packet.length - 1);
    final receivedChecksum = packet.last;
    final calculatedChecksum = calculateChecksum(dataWithoutChecksum);

    return receivedChecksum == calculatedChecksum;
  }

  /// Request device version (Command: I)
  static Uint8List requestDeviceVersion() {
    return createPacket('I');
  }

  /// Request device state (Command: A)
  static Uint8List requestDeviceState() {
    return createPacket('A');
  }

  /// Request measurement result (Command: M)
  static Uint8List requestMeasurementResult() {
    return createPacket('M');
  }

  /// Request serial number (Command: K)
  static Uint8List requestSerialNumber() {
    return createPacket('K');
  }

  /// Transmit member information (Command: B)
  static Uint8List transmitMemberInfo(String memberData) {
    final data = Uint8List.fromList(utf8.encode(memberData));
    return createPacket('B', data);
  }

  /// Transmit current time (Command: T)
  static Uint8List transmitTime(DateTime dateTime) {
    // Format: YYYYMMDDHHmmss
    final timeString = dateTime.year.toString().padLeft(4, '0') +
        dateTime.month.toString().padLeft(2, '0') +
        dateTime.day.toString().padLeft(2, '0') +
        dateTime.hour.toString().padLeft(2, '0') +
        dateTime.minute.toString().padLeft(2, '0') +
        dateTime.second.toString().padLeft(2, '0');
    final data = Uint8List.fromList(utf8.encode(timeString));
    return createPacket('T', data);
  }
}

/// Packet parser for incoming data
class PacketParser {
  final List<int> _buffer = [];
  bool _isReceiving = false;
  int _checksum = 0;

  /// Parse incoming byte
  /// Returns complete packet if available, null otherwise
  List<int>? parseByte(int byte) {
    switch (byte) {
      case AccuniqProtocol.STX:
        // Start of new packet
        _buffer.clear();
        _buffer.add(byte);
        _isReceiving = true;
        _checksum = byte;
        return null;

      case AccuniqProtocol.ETX:
        // End of data
        if (_isReceiving) {
          _buffer.add(byte);
          _checksum += byte;
        }
        return null;

      default:
        if (_isReceiving) {
          _buffer.add(byte);

          // Check if this is the checksum byte (previous byte was ETX)
          if (_buffer.length > 3 && _buffer[_buffer.length - 2] == AccuniqProtocol.ETX) {
            _isReceiving = false;
            final packet = List<int>.from(_buffer);
            _buffer.clear();

            // Verify checksum
            if (AccuniqProtocol.verifyChecksum(packet)) {
              return packet;
            } else {
              print('Checksum error!');
              return null;
            }
          } else {
            _checksum += byte;
          }
        }
        return null;
    }
  }

  /// Parse command from packet
  static String? getCommand(List<int> packet) {
    if (packet.length < 4) return null;
    return String.fromCharCode(packet[1]);
  }

  /// Get data from packet (between command and ETX)
  static String? getData(List<int> packet) {
    if (packet.length < 5) return null;

    // Find ETX position
    int etxIndex = -1;
    for (int i = 2; i < packet.length; i++) {
      if (packet[i] == AccuniqProtocol.ETX) {
        etxIndex = i;
        break;
      }
    }

    if (etxIndex == -1 || etxIndex <= 2) return null;

    final dataBytes = packet.sublist(2, etxIndex);
    return utf8.decode(dataBytes);
  }
}

