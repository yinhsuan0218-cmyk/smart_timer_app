class Zone {
  String id;
  String name;
  double temperature;
  String power;
  double energy; // ⚡ 新增：PZEM-004T 累積電能數據 (單位：kWh)

  Zone({
    required this.id, 
    required this.name, 
    this.temperature = 0.0,
    this.power = 'safe',
    this.energy = 0.0, // ⚡ 提供預設值 0.0
  });

  // 從 Firebase 的 Map 資料中解析並建立 Zone 物件
  factory Zone.fromMap(String id, Map<dynamic, dynamic> map) {
    return Zone(
      id: id,
      name: map['name'] ?? '未命名區域',
      // 確保從 Firebase 拿到的數字正確轉為 double
      temperature: (map['temperature'] ?? 0.0).toDouble(), 
      power: map['power'] ?? 'safe', // 順便補上原先建構子有但 fromMap 漏掉的 power 欄位
      energy: (map['energy'] ?? 0.0).toDouble(), // ⚡ 確保將 Firebase 拿到的電能數據轉為 double
    );
  }

  // 如果之後需要寫入 Firebase，也可以順便補上 toMap 方法
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'temperature': temperature,
      'power': power,
      'energy': energy,
    };
  }
}
