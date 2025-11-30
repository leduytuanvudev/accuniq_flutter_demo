/// Measurement result from Accuniq device
class MeasurementResult {
  final double height;              // cm
  final double weight;              // kg
  final double bodyFatMass;         // kg
  final double bodyFatPercent;      // %
  final double softLeanMass;        // kg
  final double skeletalMuscleMass;  // kg
  final double bodyWater;           // kg
  final double bmi;                 // Body Mass Index
  final double bmr;                 // Basal Metabolic Rate (kcal)
  final double bodyCellMass;        // kg
  final int age;                    // years
  final int biologicalAge;          // years
  final String gender;              // Male/Female
  final String bodyType;            // Fit, Normal, etc.
  final DateTime measureTime;

  MeasurementResult({
    required this.height,
    required this.weight,
    required this.bodyFatMass,
    required this.bodyFatPercent,
    required this.softLeanMass,
    required this.skeletalMuscleMass,
    required this.bodyWater,
    required this.bmi,
    required this.bmr,
    required this.bodyCellMass,
    required this.age,
    required this.biologicalAge,
    required this.gender,
    required this.bodyType,
    DateTime? measureTime,
  }) : measureTime = measureTime ?? DateTime.now();

  /// Parse from device response (Accuniq protocol - CSV format)
  factory MeasurementResult.fromData(List<int> data) {
    try {
      // Skip STX (0x02) and command byte ('M'), extract data until ETX (0x03)
      final startIdx = 2; // After STX and 'M'
      final endIdx = data.lastIndexOf(0x03); // Find ETX
      
      if (endIdx <= startIdx) {
        print('❌ [Parser] Invalid packet: no ETX found');
        return _defaultResult();
      }
      
      // Extract data bytes (between 'M' and ETX)
      final dataBytes = data.sublist(startIdx, endIdx);
      
      // Convert to string
      final dataString = String.fromCharCodes(dataBytes);
      
      // Parse CSV format
      final fields = dataString.split(',');
      
      if (fields.length < 20) {
        return _defaultResult();
      }
      
      // Parse measurement values
      // Based on actual data analysis from real Accuniq device:
      // Field 4: Gender (1=Male, 2=Female)
      // Field 5: Age (e.g., 027 = 27 years)
      // Field 6: Height (× 10) e.g. 1730 = 173.0 cm
      // Field 7: Weight (× 10) e.g. 0601 = 60.1 kg
      // Field 8: Skeletal Muscle Mass (× 10) e.g. 0395 = 39.5 kg
      // Field 9: Body Water (× 10) e.g. 0560 = 56.0 kg
      // Field 19: Soft Lean Mass (× 10) e.g. 0504 = 50.4 kg
      // Field 60: Body Fat % (× 10) e.g. 0101 = 10.1%
      // Field 108: Age again (for biological age calculation)
      // Field 109: BMR (no division) e.g. 1537 = 1537 kcal
      // Field 112: Body Cell Mass (× 10) e.g. 0355 = 35.5 kg
      
      final genderCode = _parseInt(fields, 4); // 1=Male, 2=Female
      final age = _parseInt(fields, 5); // Age in years
      final height = _parseValue(fields, 6, 10.0); // Height in cm (÷10)
      final weight = _parseValue(fields, 7, 10.0); // Weight in kg (÷10)
      final skeletalMuscleMass = _parseValue(fields, 8, 10.0); // Skeletal Muscle Mass (÷10)
      final bodyWater = _parseValue(fields, 9, 10.0); // Body Water (÷10)
      final softLeanMass = _parseValue(fields, 19, 10.0); // Soft Lean Mass (÷10)
      final bodyFatPercent = _parseValue(fields, 60, 10.0); // Body Fat % (÷10)
      final biologicalAge = _parseInt(fields, 108); // Biological age
      final bmr = _parseValue(fields, 109, 1.0); // BMR (no division)
      final bodyCellMass = _parseValue(fields, 112, 10.0); // Body Cell Mass (÷10)
      
      // Calculate body fat mass from weight and body fat percentage
      final bodyFatMass = weight * (bodyFatPercent / 100.0);
      
      // Calculate BMI: weight(kg) / height(m)^2
      final bmi = height > 0 ? weight / ((height / 100.0) * (height / 100.0)) : 0.0;
      
      // Determine gender
      final gender = genderCode == 1 ? 'Male' : genderCode == 2 ? 'Female' : 'Unknown';
      
      // Determine body type based on body fat percentage and gender
      String bodyType = 'Normal';
      if (gender == 'Male') {
        if (bodyFatPercent < 8) bodyType = 'Athletic';
        else if (bodyFatPercent < 15) bodyType = 'Fit';
        else if (bodyFatPercent < 20) bodyType = 'Normal';
        else if (bodyFatPercent < 25) bodyType = 'Above Average';
        else bodyType = 'High';
      } else if (gender == 'Female') {
        if (bodyFatPercent < 15) bodyType = 'Athletic';
        else if (bodyFatPercent < 22) bodyType = 'Fit';
        else if (bodyFatPercent < 30) bodyType = 'Normal';
        else if (bodyFatPercent < 35) bodyType = 'Above Average';
        else bodyType = 'High';
      }
      
      print('✅ [Parser] ========== Measurement Results ==========');
      print('✅ [Parser] Gender: $gender (Age: $age years)');
      print('✅ [Parser] Height: ${height.toStringAsFixed(1)} cm');
      print('✅ [Parser] Weight: ${weight.toStringAsFixed(1)} kg');
      print('✅ [Parser] Body Fat (PBF): ${bodyFatPercent.toStringAsFixed(1)}%');
      print('✅ [Parser] Body Fat Mass: ${bodyFatMass.toStringAsFixed(2)} kg');
      print('✅ [Parser] Soft Lean Mass: ${softLeanMass.toStringAsFixed(1)} kg');
      print('✅ [Parser] Skeletal Muscle Mass: ${skeletalMuscleMass.toStringAsFixed(1)} kg');
      print('✅ [Parser] Body Water: ${bodyWater.toStringAsFixed(1)} kg');
      print('✅ [Parser] BMI: ${bmi.toStringAsFixed(1)}');
      print('✅ [Parser] BMR: ${bmr.toStringAsFixed(0)} kcal');
      print('✅ [Parser] Body Cell Mass: ${bodyCellMass.toStringAsFixed(1)} kg');
      print('✅ [Parser] Body Type: $bodyType');
      print('✅ [Parser] Biological Age: $biologicalAge years');
      print('✅ [Parser] ===========================================');
      
      return MeasurementResult(
        height: height,
        weight: weight,
        bodyFatMass: bodyFatMass,
        bodyFatPercent: bodyFatPercent,
        softLeanMass: softLeanMass,
        skeletalMuscleMass: skeletalMuscleMass,
        bodyWater: bodyWater,
        bmi: bmi,
        bmr: bmr,
        bodyCellMass: bodyCellMass,
        age: age,
        biologicalAge: biologicalAge,
        gender: gender,
        bodyType: bodyType,
      );
    } catch (e) {
      print('❌ [Parser] Exception: $e');
      return _defaultResult();
    }
  }
  
  /// Helper: Parse a field value and divide by divisor
  static double _parseValue(List<String> fields, int index, double divisor) {
    try {
      if (index >= fields.length) return 0.0;
      final value = int.tryParse(fields[index].trim()) ?? 0;
      return value / divisor;
    } catch (e) {
      return 0.0;
    }
  }
  
  /// Helper: Parse an integer field
  static int _parseInt(List<String> fields, int index) {
    try {
      if (index >= fields.length) return 0;
      return int.tryParse(fields[index].trim()) ?? 0;
    } catch (e) {
      return 0;
    }
  }
  
  /// Helper: Create default result with zeros
  static MeasurementResult _defaultResult() {
    return MeasurementResult(
      height: 0.0,
      weight: 0.0,
      bodyFatMass: 0.0,
      bodyFatPercent: 0.0,
      softLeanMass: 0.0,
      skeletalMuscleMass: 0.0,
      bodyWater: 0.0,
      bmi: 0.0,
      bmr: 0.0,
      bodyCellMass: 0.0,
      age: 0,
      biologicalAge: 0,
      gender: 'Unknown',
      bodyType: 'Unknown',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'height': height,
      'weight': weight,
      'bodyFatMass': bodyFatMass,
      'bodyFatPercent': bodyFatPercent,
      'softLeanMass': softLeanMass,
      'skeletalMuscleMass': skeletalMuscleMass,
      'bodyWater': bodyWater,
      'bmi': bmi,
      'bmr': bmr,
      'bodyCellMass': bodyCellMass,
      'age': age,
      'biologicalAge': biologicalAge,
      'gender': gender,
      'bodyType': bodyType,
      'measureTime': measureTime.toIso8601String(),
    };
  }
}

/// Device state enum
enum DeviceState {
  ready,
  measuringWeight,
  inputMemberInfo,
  measuringBodyComposition,
  completeDisplay,
  printing,
  setting,
  calibration,
  unknown,
}

extension DeviceStateExtension on DeviceState {
  String get displayName {
    switch (this) {
      case DeviceState.ready:
        return 'Ready';
      case DeviceState.measuringWeight:
        return 'Measuring Weight';
      case DeviceState.inputMemberInfo:
        return 'Input Member Info';
      case DeviceState.measuringBodyComposition:
        return 'Measuring Body Composition';
      case DeviceState.completeDisplay:
        return 'Complete';
      case DeviceState.printing:
        return 'Printing';
      case DeviceState.setting:
        return 'Settings';
      case DeviceState.calibration:
        return 'Calibration';
      case DeviceState.unknown:
        return 'Unknown';
    }
  }

  /// Parse from device state byte
  static DeviceState fromByte(int stateByte) {
    switch (stateByte) {
      case 0x30: // '0'
        return DeviceState.ready;
      case 0x31: // '1'
        return DeviceState.measuringWeight;
      case 0x32: // '2'
      case 0x33: // '3'
      case 0x34: // '4'
        return DeviceState.inputMemberInfo;
      case 0x35: // '5'
        return DeviceState.measuringBodyComposition;
      case 0x36: // '6'
        return DeviceState.completeDisplay;
      case 0x37: // '7'
      case 0x41: // 'A'
      case 0x42: // 'B'
        return DeviceState.setting;
      case 0x43: // 'C'
        return DeviceState.calibration;
      default:
        return DeviceState.unknown;
    }
  }
}

