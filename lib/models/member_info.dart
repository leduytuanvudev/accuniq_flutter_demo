/// Member information for measurement
class MemberInfo {
  final String id;
  final String name;
  final int age;
  final String gender; // 'M' or 'F'
  final double height; // cm

  MemberInfo({
    required this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.height,
  });

  /// Convert to string format for Accuniq device
  String toDataString() {
    return '$id,$name,$age,$gender,$height';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'age': age,
      'gender': gender,
      'height': height,
    };
  }

  factory MemberInfo.fromJson(Map<String, dynamic> json) {
    return MemberInfo(
      id: json['id'],
      name: json['name'],
      age: json['age'],
      gender: json['gender'],
      height: json['height'],
    );
  }
}

