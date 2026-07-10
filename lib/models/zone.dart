class Zone {
  String id;
  String name;
  double temperature;

  Zone({
    required this.id, 
    required this.name, 
    this.temperature = 0.0,
  });

  // 從 Firebase 的 Map 資料中解析並建立 Zone 物件
  factory Zone.fromMap(String id, Map<dynamic, dynamic> map) {
    return Zone(
      id: id,
      name: map['name'] ?? '未命名區域',
      // 確保從 Firebase 拿到的數字正確轉為 double
      temperature: (map['temperature'] ?? 0.0).toDouble(), 
    );
  }
}
