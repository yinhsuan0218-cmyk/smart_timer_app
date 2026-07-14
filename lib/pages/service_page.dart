import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'schedule_page.dart';
import '../services/mqtt_service.dart';
import 'dart:math' as math;
import 'dart:async'; // ⏱️ 新增：用於 Timer
import 'package:fl_chart/fl_chart.dart'; // 📊 新增：圖表套件

class ServicePage extends StatefulWidget {
  final String zoneId;   
  final String zoneName; 
  final String mqttTopic; 

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
  String? uid; 
  final MqttService _mqttService = MqttService(); 
  int _currentDeviceCount = 0;

  static const double tempSafeMin = 0.0; 
  static const double tempWarnMin = 60.0; 
  static const double tempDangerMin = 80.0; 

  double _currentTemperature = 70.0; 
  bool _isDangerTriggered = false;   
  String _currentPowerState = 'safe';

  // 📊 趨勢圖相關變數
  final List<double> _tempHistory = []; // 儲存溫度歷史紀錄
  Timer? _historyTimer; // 20秒定時器
  final int _maxDataPoints = 10; // 圖表最多顯示最近 10 筆資料

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser?.uid;
    _mqttService.connect();
    
    if (uid != null) {
      _zoneRef = FirebaseDatabase.instance.ref('users/$uid/zones/${widget.zoneId}');
      _devicesRef = _zoneRef.child('devices');
    } else {
      _zoneRef = FirebaseDatabase.instance.ref('zones/${widget.zoneId}');
      _devicesRef = _zoneRef.child('devices');
    }
    
    _listenToTemperature();
    _listenToPowerState();
    _startTemperatureTracking(); // ⏱️ 啟動每20秒紀錄一次的定時器
  }

  @override
  void dispose() {
    _historyTimer?.cancel(); // 🛑 記得銷毀定時器，避免記憶體洩漏
    super.dispose();
  }

  // ⏱️ 新增：每 20 秒捕捉一次當前溫度寫入趨勢陣列
  void _startTemperatureTracking() {
    // 初始先加入一筆當前值
    _tempHistory.add(_currentTemperature);

    _historyTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      setState(() {
        _tempHistory.add(_currentTemperature);
        // 如果歷史紀錄超出最大限制，就把最舊的（index 0）丟掉，維持圖表滾動感
        if (_tempHistory.length > _maxDataPoints) {
          _tempHistory.removeAt(0);
        }
      });
    });
  }

  // 監聽溫度
  void _listenToTemperature() {
    _zoneRef.child('temperature').onValue.listen((event) {
      if (event.snapshot.value != null) {
        String rawValue = event.snapshot.value.toString().trim();
        double temp = rawValue.isEmpty ? 0.0 : (double.tryParse(rawValue) ?? 0.0);

        setState(() {
          _currentTemperature = temp;
        });
        
        _checkSafetyMechanism(temp);
      }
    });
  }

  // 監聽後端運算的 power 狀態
  void _listenToPowerState() {
    _zoneRef.child('power').onValue.listen((event) {
      if (event.snapshot.value != null) {
        setState(() {
          _currentPowerState = event.snapshot.value.toString();
        });
      }
    });
  }

  void _checkSafetyMechanism(double currentTemp) {
    if (currentTemp >= tempDangerMin) {
      if (!_isDangerTriggered) {
        _isDangerTriggered = true; 
        _executeEmergencyShutdown();
      }
    } else {
      _isDangerTriggered = false; 
    }
  }

  void _pushNotification({required String title, required String content, required String type}) {
    if (uid == null) return;
    
    final notificationRef = FirebaseDatabase.instance.ref('users/$uid/notifications').push();
    notificationRef.set({
      'title': title,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(), 
      'type': type, 
      'status': 'unread',
      'zone_name': widget.zoneName,
    });
  }

  Future<void> _executeEmergencyShutdown() async {
    final snapshot = await _devicesRef.get();
    if (snapshot.exists && snapshot.value != null) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      data.forEach((deviceId, value) {
        _devicesRef.child(deviceId).update({'is_active': false});
        _mqttService.publishCommand(widget.mqttTopic, "$deviceId:OFF");
      });
    }

    if (uid == null) return;
    
    final notificationRef = FirebaseDatabase.instance.ref('users/$uid/notifications').push();
    await notificationRef.set({
      'zoneId': widget.zoneId,
      'title': '🚨 危險！溫度過高自動斷電',
      'content': '區域【${widget.zoneName}】目前環境溫度已達 ${_currentTemperature.toStringAsFixed(1)}°C。系統已強制關閉所有高負載裝置！',
      'timestamp': DateTime.now().toIso8601String(),
      'type': 'danger',
      'status': 'unread', 
      'zone_name': widget.zoneName,
      'temperature': _currentTemperature.toStringAsFixed(1),
    });
  }

  void _toggleDevice(String deviceId, bool status) {
    _devicesRef.child(deviceId).update({'is_active': status});

    String command = status ? "ON" : "OFF";
    _mqttService.publishCommand(widget.mqttTopic, "$deviceId:$command");
    
    String statusText = status ? "開啟" : "關閉";
    _pushNotification(
      title: '🔌 設備狀態變更',
      content: '您手動了$statusText【${widget.zoneName}】環境中的設備（ID: $deviceId）。',
      type: 'info', 
    );
  }

  Map<String, dynamic> _getTemperatureStatus(double temp) {
    if (temp >= tempDangerMin) {
      return {'text': 'Danger', 'color': Colors.red, 'icon': Icons.gpp_bad_rounded};
    } else if (temp >= tempWarnMin) {
      return {'text': 'Warn', 'color': Colors.amber, 'icon': Icons.gpp_maybe_rounded};
    } else {
      return {'text': 'Safe', 'color': Colors.green, 'icon': Icons.gpp_good_rounded};
    }
  }

  void addDevice() {
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
              textInputAction: TextInputAction.done, 
              onSubmitted: (_) => submitNewDevice(),  
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
            onPressed: submitNewDevice, 
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

          _currentDeviceCount = deviceList.length;

          return Column(
            children: [
              // 🌡️ 頂部儀表板區塊
              _buildTemperaturePanel(statusColor, statusText, statusData['icon']),
              
              // 📊 新增：每 20 秒更新的溫度歷史趨勢圖
              _buildTemperatureChart(),

              // 🔌 耗電狀態看板（插座 / 爆炸插座效果）
              _buildPowerStatusPanel(),

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

  Widget _buildTemperaturePanel(Color statusColor, String statusText, IconData statusIcon) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 80, 
            width: 140, 
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
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  const Text('Temp : ', style: TextStyle(fontSize: 15, color: Colors.black, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white, 
                      borderRadius: BorderRadius.circular(8), 
                      border: Border.all(color: Colors.black, width: 1.5), 
                    ),
                    child: Text('${_currentTemperature.toStringAsFixed(1)} °C', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              
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

  // 📊 新增：折線趨勢圖控制項 UI
  Widget _buildTemperatureChart() {
    // 將儲存的 double 陣列轉換為 fl_chart 需要的 FlSpot 座標
    List<FlSpot> spots = [];
    for (int i = 0; i < _tempHistory.length; i++) {
      spots.add(FlSpot(i.toDouble(), _tempHistory[i]));
    }

    // 如果剛開畫面還沒有收集到資料，就先顯示載入中
    if (spots.isEmpty) {
      return const SizedBox(
        height: 140,
        child: Center(child: Text("正在收集溫度數據 (每20秒更新)...", style: TextStyle(color: Colors.grey, fontSize: 12))),
      );
    }

    return Container(
      height: 140,
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(12, 16, 24, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.withOpacity(0.15),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // 隱藏底部雜亂的 index 軸點
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: 20, // 縱軸每 20 度畫一條橫線線標
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toInt()}°C',
                    style: const TextStyle(color: Colors.black45, fontSize: 10, fontWeight: FontWeight.bold),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (_maxDataPoints - 1).toDouble(),
          minY: 0,
          maxY: 100, // 與儀表板刻度一致
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true, // 曲線平滑
              color: _currentTemperature >= tempDangerMin 
                  ? Colors.red 
                  : (_currentTemperature >= tempWarnMin ? Colors.amber : Colors.blue),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true), // 顯示數據點的小圓圈
              belowBarData: BarAreaData(
                show: true,
                color: (_currentTemperature >= tempDangerMin 
                        ? Colors.red 
                        : (_currentTemperature >= tempWarnMin ? Colors.amber : Colors.blue))
                    .withOpacity(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🔌 動態耗電狀態看板 UI
  Widget _buildPowerStatusPanel() {
    bool isWaste = _currentPowerState == 'waste';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isWaste ? const Color(0xFFFFF3E0) : const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isWaste ? const Color(0xFFD84315) : Colors.black26, 
          width: isWaste ? 2.0 : 1.0
        ),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: isWaste ? const EdgeInsets.only(top: 6.0) : EdgeInsets.zero,
                child: Icon(
                  Icons.power, 
                  size: 38, 
                  color: isWaste ? const Color(0xFF424242) : Colors.green[600]
                ),
              ),
              if (isWaste)
                const Positioned(
                  right: 0,
                  top: 0,
                  child: Icon(
                    Icons.volcano, 
                    size: 24, 
                    color: Color(0xFFFF3D00),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isWaste ? "💥 偵測到電力過度浪費！" : "🌱 用電量處於安全範圍",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isWaste ? const Color(0xFFD84315) : Colors.green[800],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isWaste ? "此區域目前呈現嚴重耗電，請檢查是否有無人使用的電器正開著。" : "目前本區域的實時總耗電量正常。",
                  style: TextStyle(
                    fontSize: 12,
                    color: isWaste ? const Color(0xFFBF360C) : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
                    Switch(
                      value: isActive,
                      activeColor: Colors.black,
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

// (GaugePainter 保持不變，故省略以節省篇幅)

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
    final double maxTempRef = 100.0; 
    
    double warnStartPercent = (warnMin - safeMin) / maxTempRef;
    double dangerStartPercent = (dangerMin - safeMin) / maxTempRef;

    Paint arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24.0; 

    arcPaint.color = Colors.green.withOpacity(0.3);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 12),
      3.14159, 
      3.14159 * warnStartPercent,
      false,
      arcPaint,
    );

    arcPaint.color = Colors.amber.withOpacity(0.3);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 12),
      3.14159 + (3.14159 * warnStartPercent),
      3.14159 * (dangerStartPercent - warnStartPercent),
      false,
      arcPaint,
    );

    arcPaint.color = Colors.red.withOpacity(0.3);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 12),
      3.14159 + (3.14159 * dangerStartPercent),
      3.14159 * (1.0 - dangerStartPercent),
      false,
      arcPaint,
    );

    Paint borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      3.14159,
      3.14159,
      false,
      borderPaint,
    );
    canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), borderPaint);

    for (int i = 0; i <= 4; i++) {
      double angle = 3.14159 + (3.14159 / 4 * i);
      double startX = center.dx + (radius - 8) * math.cos(angle);
      double startY = center.dy + (radius - 8) * math.sin(angle);
      double endX = center.dx + radius * math.cos(angle);
      double endY = center.dy + radius * math.sin(angle);
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), borderPaint);
    }

    Paint needlePaint = Paint()
      ..color = Colors.black.withOpacity(0.8)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    double currentPercent = (temperature / maxTempRef).clamp(0.0, 1.0);
    double needleAngle = 3.14159 + (3.14159 * currentPercent);

    double needleLength = radius - 15;
    double needleX = center.dx + needleLength * math.cos(needleAngle);
    double needleY = center.dy + needleLength * math.sin(needleAngle);

    canvas.drawLine(center, Offset(needleX, needleY), needlePaint);
    canvas.drawCircle(center, 6.0, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(covariant GaugePainter oldDelegate) {
    return oldDelegate.temperature != temperature;
  }
}
