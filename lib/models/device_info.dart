/// Device information model
class DeviceInfo {
  final String deviceName;
  final String region;
  final String protocolVersion;
  final String algorithmVersion;
  final String regionCode;
  final String serialNumber;

  DeviceInfo({
    required this.deviceName,
    required this.region,
    required this.protocolVersion,
    required this.algorithmVersion,
    required this.regionCode,
    this.serialNumber = '',
  });

  factory DeviceInfo.fromString(String data) {
    // Parse: "BC720&AP&1.4&1.0&K&0"
    final parts = data.split('&');
    if (parts.length < 4) {
      throw Exception('Invalid device info format');
    }

    return DeviceInfo(
      deviceName: parts[0],
      region: parts[1],
      protocolVersion: parts[2],
      algorithmVersion: parts[3],
      regionCode: parts.length > 4 ? parts[4] : '',
    );
  }

  DeviceInfo copyWith({String? serialNumber}) {
    return DeviceInfo(
      deviceName: deviceName,
      region: region,
      protocolVersion: protocolVersion,
      algorithmVersion: algorithmVersion,
      regionCode: regionCode,
      serialNumber: serialNumber ?? this.serialNumber,
    );
  }

  @override
  String toString() {
    return '$deviceName $region v$protocolVersion (Serial: ${serialNumber.isEmpty ? "N/A" : serialNumber})';
  }
}

