import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ★ 新增：引入 Auth
import 'schedule_page.dart'; // ★ 確保有這行
import '../services/mqtt_service.dart'; // ★ 確保路徑正確，引入你的 MQTT 服務
import 'dart:math' as math;
class ServicePage extends StatefulWidget {
  final String zoneId;   // 知道是哪個區域 (例如 zone_01)
  final String zoneName; 
  final String mqttTopic; // ★ 新增：接收來自 ZonePage 的主題// 知道區域名字 (例如 客廳)

  // ★ 修正後的建構函式
  const ServicePage({
    super.key,
    required this.zoneId,
    required this.zoneName,
    required this.mqttTopic,
  });

  @override
  State<ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends State<ServicePage> {
  late DatabaseReference _devicesRef; 
  late DatabaseReference _zoneRef;
  String? uid; // ★ 新增用來存 UID
  final MqttService _mqttService = MqttService(); // ★ 初始化 MQTT 服務
  int _currentDeviceCount = 0;
  // --- 溫度設定防錯門檻（可依硬體實驗自由調整常數） ---
  static const double tempSafeMin = 0.0; // a
  static const double tempWarnMin = 60.0; // b
  static const double tempDangerMin = 80.0; // c

  // 內部狀態變數
  double _currentTemperature = 25.0; // 預設初始溫度
  bool _isDangerTriggered = false;   // 避免危險狀態重複觸發自動斷電
  @override
  void initState() {
    super.initState();
    // ★ 抓取目前登入使用者的 UID
    uid = FirebaseAuth.instance.currentUser?.uid;
    // 連接 MQTT Broker
    _mqttService.connect();
    // ★ 關鍵修改：路徑變成 'users/你的UID/zones/區域ID/devices'
    if (uid != null) {
    _zoneRef = FirebaseDatabase.instance.ref('users/$uid/zones/${widget.zoneId}');
    _devicesRef = _zoneRef.child('devices');
  } else {
    _zoneRef = FirebaseDatabase.instance.ref('zones/${widget.zoneId}');
    _devicesRef = _zoneRef.child('devices');
  }
    // 監聽該 Zone 的即時溫度變化
    _listenToTemperature();
  }

  void _listenToTemperature() {
    _zoneRef.child('temperature').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final double? temp = double.tryParse(event.snapshot.value.toString());
        if (temp != null) {
          setState(() {
            _currentTemperature = temp;
          });
          // 檢查是否觸發 Danger 警報機制
          _checkSafetyMechanism(temp);
        }
      }
    });
  }

  // 安全防護自動化核心邏輯
  void _checkSafetyMechanism(double currentTemp) {
    if (currentTemp >= tempDangerMin) {
      if (!_isDangerTriggered) {
        _isDangerTriggered = true; // 鎖定防重複觸發
        _executeEmergencyShutdown();
      }
    } else {
      _isDangerTriggered = false; // 溫度降回安全線後解鎖
    }
  }

  // 執行危險狀態：全關 + 跳出通知警告
  Future<void> _executeEmergencyShutdown() async {
    // 1. 抓取當前所有裝置，將它們全數關閉
    final snapshot = await _devicesRef.get();
    if (snapshot.exists && snapshot.value != null) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      data.forEach((deviceId, value) {
        // 更新 Firebase
        _devicesRef.child(deviceId).update({'is_active': false});
        // 發送 MQTT 實體斷電指令
        _mqttService.publishCommand(widget.mqttTopic, "$deviceId:OFF");
      });
    }

    // 2. 畫面上彈出最嚴厲的暗紅色 Danger 警告視窗
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false, // 強制使用者一定要按確認
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF8B0000), // 暗紅色背景
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
            SizedBox(width: 8),
            Text('危險！溫度過高', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '目前環境溫度已達 ${_currentTemperature.toStringAsFixed(1)}°C（超過危險值 $tempDangerMin°C）。\n系統已啟動安全保護：\n⚠️ 已自動關閉該區域內所有高負載裝置！',
          style: const TextStyle(color: Colors.white70, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('收到警告', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 取得當前溫度對應的顏色與文字狀態
  Map<String, dynamic> _getTemperatureStatus(double temp) {
    if (temp >= tempDangerMin) {
      return {'text': 'Danger', 'color': Colors.red, 'icon': Icons.gpp_bad_rounded};
    } else if (temp >= tempWarnMin) {
      return {'text': 'Warn', 'color': Colors.amber, 'icon': Icons.gpp_maybe_rounded};
    } else {
      return {'text': 'Safe', 'color': Colors.green, 'icon': Icons.gpp_good_rounded};
    }
  }
  // ★ 新增：處理開關切換並發送 MQTT
  void _toggleDevice(String deviceId, bool status) {
    // 1. 更新 Firebase 狀態（讓 UI 跟著動）
    _devicesRef.child(deviceId).update({'is_active': status});

    // 2. 發送 MQTT 指令到指定的 Topic
    // 指令格式建議： "DEVICE_ID:ON" 或 "DEVICE_ID:OFF"
    String command = status ? "ON" : "OFF";
    _mqttService.publishCommand(widget.mqttTopic, "$deviceId:$command");
    
    print("發送 MQTT 指令到 ${widget.mqttTopic} : $deviceId:$command");
  }
  // 輔助函式：時間格式化
  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // 新增裝置（加入數量限制邏輯與 Enter 鍵觸發）
  void addDevice() {
    // 關鍵限制：如果目前的裝置數量已經達到或超過 2 個，直接攔截並跳出警告
    if (_currentDeviceCount >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ 每個智慧插座區域最多只能綁定 2 個裝置！'),
          backgroundColor: Color(0xFF8B0000),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final TextEditingController idController = TextEditingController();

    // 抽出核心新增邏輯，供按鈕與鍵盤 Enter 共用
    void submitNewDevice() {
      final String deviceId = idController.text.trim();
      if (deviceId.isNotEmpty) {
        _devicesRef.child(deviceId).set({
          'is_active': false,
          'timer_start': "",
          'timer_end': "",
        });
        Navigator.pop(context);
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('新增裝置', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idController,
              textInputAction: TextInputAction.done, // 將鍵盤右下角按鈕改為「完成」圖示
              onSubmitted: (_) => submitNewDevice(),  // ★ 關鍵：按下鍵盤 Enter/完成鍵時觸發
              decoration: const InputDecoration(
                labelText: '自訂 ID',
                hintText: '例如：light_01',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: submitNewDevice, // 使用共用的新增邏輯
            child: const Text('新增', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    final statusData = _getTemperatureStatus(_currentTemperature);
    final Color statusColor = statusData['color'];
    final String statusText = statusData['text'];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.zoneName, style: const TextStyle(fontWeight: FontWeight.bold)), 
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      // 💡 注意：我們把 Scaffold 原本的 floatingActionButton 拿掉
      body: StreamBuilder(
        stream: _devicesRef.onValue,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("連線錯誤"));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          List<Map<String, dynamic>> deviceList = [];
          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            final rawData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
            rawData.forEach((key, value) {
              final device = Map<String, dynamic>.from(value);
              device['id'] = key;
              deviceList.add(device);
            });
          }

          // 更新裝置數量
          _currentDeviceCount = deviceList.length;

          // 💡 使用 Stack：這樣當 Firebase 數據一變，整個畫面連同按鈕都會「同時」完美重繪！
          return Column(
            children: [
              // 🌡️ 頂部手繪感溫度儀表板區塊面版
              _buildTemperaturePanel(statusColor, statusText, statusData['icon']),
              const Divider(height: 1, thickness: 1, color: Color(0xFFF5F5F5)),
              
              // 🔌 下方裝置清單區塊
              Expanded(
                child: Stack(
                  children: [
                    deviceList.isEmpty 
                      ? const Center(child: Text("此區域尚無裝置"))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), 
                          itemCount: deviceList.length,
                          itemBuilder: (context, index) => _buildDeviceCard(deviceList[index]),
                        ),
                    
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: FloatingActionButton.extended(
                        onPressed: addDevice,
                        label: Text(_currentDeviceCount >= 2 ? '裝置已滿 (2/2)' : '新增裝置'),
                        icon: Icon(_currentDeviceCount >= 2 ? Icons.block : Icons.add),
                        backgroundColor: _currentDeviceCount >= 2 ? Colors.grey[300] : Colors.white,
                        foregroundColor: _currentDeviceCount >= 2 ? Colors.black38 : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
 // --- 💡 修改後：完美呈現手繪感儀表板的 Widget ---
  Widget _buildTemperaturePanel(Color statusColor, String statusText, IconData statusIcon) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black),
      ),
      child: Column(
        children: [
          // 📊 手繪半圓形儀表板本體
          SizedBox(
            height: 80, // 半圓形稍微調整高度
            width: 140, // 寬度拉長以符合半圓比例
            child: CustomPaint(
              painter: GaugePainter(
                temperature: _currentTemperature,
                safeMin: tempSafeMin,
                warnMin: tempWarnMin,
                dangerMin: tempDangerMin,
              ),
            ),
          ),
          const SizedBox(height: 15),
          
          // 欄位排版（符合手繪稿的 Temp: [ 25°C ]  Status: [ Safe ] 橫向排列）
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 溫度顯示欄位
              Row(
                children: [
                  const Text('Temp : ', style: TextStyle(fontSize: 15, color: Colors.black, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white, 
                      borderRadius: BorderRadius.circular(8), 
                      border: Border.all(color: Colors.black, width: 1.5), // 帶點黑邊手繪感
                    ),
                    child: Text('${_currentTemperature.toStringAsFixed(1)} °C', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              
              // 狀態燈與字樣顯示欄位
              Row(
                children: [
                  const Text('Status : ', style: TextStyle(fontSize: 15, color: Colors.black, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor, 
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Icon(statusIcon, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          statusText, 
                          style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
  // 裝置卡片 UI 
  Widget _buildDeviceCard(Map<String, dynamic> device) {
    bool isActive = device['is_active'] ?? false;
    String id = device['id'];
    String start = device['timer_start'] ?? "";
    String end = device['timer_end'] ?? "";
    bool hasSchedule = start.isNotEmpty || end.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Dismissible(
        key: Key(id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (d) async => await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('刪除 $id?'), content: const Text('確定移除嗎？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("取消")),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("刪除", style: TextStyle(color: Colors.red))),
            ],
          )
        ),
        onDismissed: (_) => _devicesRef.child(id).remove(),
        background: Container(
          color: Colors.red[100], alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete, color: Colors.red),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: isActive ? [BoxShadow(color: Colors.yellow.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))] : [],
          ),
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.power, color: isActive ? Colors.orange : Colors.grey),
                title: Text(id, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(isActive ? "開啟中" : "已關閉"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ★ 升級版：點擊日曆圖示，直接跳轉到我們最強的排程頁面
                    IconButton(
                      icon: Icon(Icons.date_range, color: hasSchedule ? Colors.blue : Colors.grey[300]),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SchedulePage(
                              zoneId: widget.zoneId,
                              deviceId: id,
                            ),
                          ),
                        );
                      },
                    ),
                    // 修改後 ★
                    Switch(
                      value: isActive,
                      activeColor: Colors.black,
                      // 如果處於危險過熱狀態，不允許手動開啟開關做二次防呆
                      onChanged: _currentTemperature >= tempDangerMin ? null : (val) => _toggleDevice(id, val),
                    ),
                  ],
                ),
              ),
              if (hasSchedule)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      Divider(color: Colors.grey[100]),
                      Row(children: [const Icon(Icons.play_circle, size: 14, color: Colors.blue), const SizedBox(width: 4), Text("開: $start", style: const TextStyle(fontSize: 12))]),
                      const SizedBox(height: 4),
                      Row(children: [const Icon(Icons.stop_circle, size: 14, color: Colors.red), const SizedBox(width: 4), Text("關: $end", style: const TextStyle(fontSize: 12))]),
                    ],
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }
}
// 🎨 專門用來畫半圓形儀表板與指針的 Painter
class GaugePainter extends CustomPainter {
  final double temperature;
  final double safeMin;
  final double warnMin;
  final double dangerMin;

  GaugePainter({
    required this.temperature,
    required this.safeMin,
    required this.warnMin,
    required this.dangerMin,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height);
    final double radius = size.width / 2;

    // 1. 繪製半圓底色背景區間 (Safe:綠, Warn:黃, Danger:紅)
    final double maxTempRef = 100.0; // 假設儀表板最大度數為 100 度
    
    // 計算各區間弧度比例
    double warnStartPercent = (warnMin - safeMin) / maxTempRef;
    double dangerStartPercent = (dangerMin - safeMin) / maxTempRef;

    Paint arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24.0; // 弧帶的粗細

    // Safe 區間 (綠色)
    arcPaint.color = Colors.green.withOpacity(0.3);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 12),
      3.14159, // 從 180 度開始 (左側)
      3.14159 * warnStartPercent,
      false,
      arcPaint,
    );

    // Warn 區間 (黃色/橘色)
    arcPaint.color = Colors.amber.withOpacity(0.3);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 12),
      3.14159 + (3.14159 * warnStartPercent),
      3.14159 * (dangerStartPercent - warnStartPercent),
      false,
      arcPaint,
    );

    // Danger 區間 (紅色)
    arcPaint.color = Colors.red.withOpacity(0.3);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 12),
      3.14159 + (3.14159 * dangerStartPercent),
      3.14159 * (1.0 - dangerStartPercent),
      false,
      arcPaint,
    );

    // 2. 繪製外圍黑框與刻度線 (手繪風格)
    Paint borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // 繪製半圓外框形
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      3.14159,
      3.14159,
      false,
      borderPaint,
    );
    // 繪製底部橫線
    canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), borderPaint);

    // 繪製 5 條簡單刻度
    for (int i = 0; i <= 4; i++) {
      double angle = 3.14159 + (3.14159 / 4 * i);
      double startX = center.dx + (radius - 8) * math.cos(angle);
      double startY = center.dy + (radius - 8) * math.sin(angle);
      double endX = center.dx + radius * math.cos(angle);
      double endY = center.dy + radius * math.sin(angle);
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), borderPaint);
    }

    // 3. 繪製中心黑點與指針
    Paint needlePaint = Paint()
      ..color = Colors.black.withOpacity(0.8)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    // 依據當前溫度計算指針角度 (最小 0.0, 最大 maxTempRef)
    double currentPercent = (temperature / maxTempRef).clamp(0.0, 1.0);
    double needleAngle = 3.14159 + (3.14159 * currentPercent);


    double needleLength = radius - 15;
    double needleX = center.dx + needleLength * math.cos(needleAngle);
    double needleY = center.dy + needleLength * math.sin(needleAngle);

    // 畫指針箭頭主線
    canvas.drawLine(center, Offset(needleX, needleY), needlePaint);
    // 畫中心黑點
    canvas.drawCircle(center, 6.0, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(covariant GaugePainter oldDelegate) {
    return oldDelegate.temperature != temperature;
  }
}
