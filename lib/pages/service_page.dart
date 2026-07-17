import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'schedule_page.dart';
import '../services/mqtt_service.dart';
import 'dart:math' as math;
import 'dart:async'; 
import 'package:fl_chart/fl_chart.dart'; 

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

  // 📊 溫度趨勢圖相關變數
  final List<Map<String, dynamic>> _tempHistory = []; 
  final int _maxDataPoints = 8; 
  StreamSubscription? _tempSubscription; 

  // 📌 宣告一個用來通知 BottomSheet 實時重繪的 StateSetter
  StateSetter? _sheetStateSetter;

  // 📊 耗電趨勢圖相關變數
  final List<Map<String, dynamic>> _powerHistory = []; 
  final int _maxPowerPoints = 8; // 最多顯示 8 筆紀錄
  StateSetter? _powerSheetStateSetter; // 用於通知耗電 BottomSheet 實時重繪

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
  }

  @override
  void dispose() {
    _tempSubscription?.cancel(); 
    super.dispose();
  }

  // ⏱️ 實時監聽溫度
  void _listenToTemperature() {
    _tempSubscription = _zoneRef.child('temperature').onValue.listen((event) {
      if (event.snapshot.value != null) {
        String rawValue = event.snapshot.value.toString().trim();
        double temp = rawValue.isEmpty ? 0.0 : (double.tryParse(rawValue) ?? 0.0);

        final DateTime now = DateTime.now();
        final String formattedTime = 
            "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

        setState(() {
          _currentTemperature = temp;

          _tempHistory.add({
            'temp': temp,
            'time': formattedTime,
          });

          if (_tempHistory.length > _maxDataPoints) {
            _tempHistory.removeAt(0);
          }
        });

        // 🔔 如果 BottomSheet 此時是打開狀態，強制觸發它的局部重繪
        if (_sheetStateSetter != null) {
          _sheetStateSetter!(() {});
        }
        
        _checkSafetyMechanism(temp);
      }
    });
  }

  // 🔌 實時監聽耗電能耗與動態狀態判定
void _listenToPowerState() {
  _zoneRef.child('energy').onValue.listen((event) {
    if (event.snapshot.value != null) {
      String rawValue = event.snapshot.value.toString().trim();
      double energy = rawValue.isEmpty ? 0.0 : (double.tryParse(rawValue) ?? 0.0);

      final DateTime now = DateTime.now();
      final String formattedTime = 
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

      // 1. 計算目前處於「開啟狀態（is_active）」的裝置數量
      int activeDeviceCount = 0;
      _devicesRef.get().then((snapshot) {
        if (snapshot.exists && snapshot.value != null) {
          final data = snapshot.value as Map<dynamic, dynamic>;
          data.forEach((key, value) {
            final device = Map<String, dynamic>.from(value);
            if (device['is_active'] == true) {
              activeDeviceCount++;
            }
          });
        }

        // 2. 根據當前開啟數量與能耗值（energy）進行動態判定
        String power = 'safe';
        
        if (activeDeviceCount == 0) {
          // 沒有裝置在運作，能耗理應接近 0W（給 2W 容許誤差值）
          if (energy > 2.0) {
            power = 'waste'; // 異常漏電或不該供電時有能耗
          } else {
            power = 'safe';
          }
        } else if (activeDeviceCount == 1) {
          // 單一裝置運作，安全能耗上限設在 1200W
          if (energy > 1200.0) {
            power = 'waste';
          } else {
            power = 'safe';
          }
        } else if (activeDeviceCount >= 2) {
          // 兩個裝置同時運作，總安全能耗上限設在 1600W
          if (energy > 1600.0) {
            power = 'waste';
          } else {
            power = 'safe';
          }
        }

        setState(() {
          _currentPowerState = power; // 更新狀態變數（畫面上判斷 isWaste 會用到）

          _powerHistory.add({
            'power': energy, // 圖表仍使用當下的數值進行繪製
            'time': formattedTime,
          });

          if (_powerHistory.length > _maxPowerPoints) {
            _powerHistory.removeAt(0);
          }
        });

        // 🔔 如果耗電 BottomSheet 此時是打開狀態，強制觸發它的局部重繪
        if (_powerSheetStateSetter != null) {
          _powerSheetStateSetter!(() {});
        }
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

  }

  void _toggleDevice(String deviceId, bool status) {
    _devicesRef.child(deviceId).update({'is_active': status});

    String command = status ? "ON" : "OFF";
    _mqttService.publishCommand(widget.mqttTopic, "$deviceId:$command");
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

  // 📈 彈出式溫度趨勢圖
  void _showChartBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, 
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            _sheetStateSetter = setModalState;

            return Container(
              margin: const EdgeInsets.all(16), 
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.black, width: 2), 
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min, 
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.analytics_outlined, color: Colors.black, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            "${widget.zoneName} 實時溫度趨勢",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.black),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTemperatureChart(),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      _sheetStateSetter = null;
    });
  }

  // ⚡ 彈出式耗電趨勢圖
  void _showPowerChartBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, 
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            _powerSheetStateSetter = setModalState;

            return Container(
              margin: const EdgeInsets.all(16), 
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.black, width: 2), 
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bolt_rounded, color: Colors.amber, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            "${widget.zoneName} 實時功率趨勢",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.black),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildPowerChart(),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      _powerSheetStateSetter = null; 
    });
  }

  // 📊 耗電折線趨勢圖
  Widget _buildPowerChart() {
    List<FlSpot> spots = [];
    for (int i = 0; i < _powerHistory.length; i++) {
      spots.add(FlSpot(i.toDouble(), _powerHistory[i]['power']));
    }

    if (spots.isEmpty) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        child: const Text("正在收集耗電數據中...", style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }

    double maxPowerInHistory = _powerHistory.map((e) => e['power'] as double).reduce((a, b) => a > b ? a : b);
    double maxY = maxPowerInHistory < 10 ? 10 : (maxPowerInHistory * 1.2); 

    return Container(
      height: 180, 
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(4, 16, 20, 4),
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
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toInt()}W',
                    style: const TextStyle(color: Colors.black45, fontSize: 10, fontWeight: FontWeight.bold),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 2.0, 
                getTitlesWidget: (value, meta) {
                  final int index = value.round();
                  if (index >= 0 && index < _powerHistory.length) {
                    try {
                      final dynamic entry = _powerHistory[index];
                      if (entry is Map) {
                        final String? rawTime = entry['time']?.toString();
                        if (rawTime != null) {
                          List<String> parts = rawTime.split(':');
                          String timeLabel = parts.length >= 2 ? "${parts[0]}:${parts[1]}" : rawTime;

                          return Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(
                              timeLabel,
                              style: const TextStyle(color: Colors.black38, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      return const SizedBox.shrink();
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (_maxPowerPoints - 1).toDouble(),
          minY: 0,
          maxY: maxY, 
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true, 
              color: Colors.green, 
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true), 
              belowBarData: BarAreaData(
                show: true,
                color: Colors.green.withOpacity(0.1),
              ),
            ),
          ],
        ),
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
              // 移除容易造成 nested json 循環引用的寫法，改為儲存裝置總量
              deviceList.add(device);
            });
          }

          _currentDeviceCount = deviceList.length;

          return Column(
            children: [
              _buildTemperaturePanel(statusColor, statusText, statusData['icon']),
              _buildPowerStatusPanel(),
              const Divider(height: 1, thickness: 1, color: Color(0xFFF5F5F5)),
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

  // 🌡️ 溫度儀表板
  Widget _buildTemperaturePanel(Color statusColor, String statusText, IconData statusIcon) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black, width: 1.5),
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
          const SizedBox(height: 12),
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
                    child: Text('${_currentTemperature.toStringAsFixed(1)} °C', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(width: 16),
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
                          style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _showChartBottomSheet,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(2, 2), 
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.analytics_outlined, size: 16, color: Colors.black),
                  SizedBox(width: 6),
                  Text(
                    '查看實時溫度趨勢圖', 
                    style: TextStyle(fontSize: 13, color: Colors.black, fontWeight: FontWeight.bold)
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 📊 溫度折線趨勢圖 widget
  Widget _buildTemperatureChart() {
    List<FlSpot> spots = [];
    for (int i = 0; i < _tempHistory.length; i++) {
      spots.add(FlSpot(i.toDouble(), _tempHistory[i]['temp']));
    }

    if (spots.isEmpty) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        child: const Text("正在收集溫度數據中...", style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }

    return Container(
      height: 180, 
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(4, 16, 20, 4),
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
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: 20, 
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toInt()}°C',
                    style: const TextStyle(color: Colors.black45, fontSize: 10, fontWeight: FontWeight.bold),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 2.0, 
                getTitlesWidget: (value, meta) {
                  final int index = value.round();
                  
                  if (index >= 0 && index < _tempHistory.length) {
                    try {
                      final dynamic entry = _tempHistory[index];
                      if (entry is Map) {
                        final String? rawTime = entry['time']?.toString();
                        if (rawTime != null) {
                          List<String> parts = rawTime.split(':');
                          String timeLabel = parts.length >= 2 ? "${parts[0]}:${parts[1]}" : rawTime;

                          return Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(
                              timeLabel,
                              style: const TextStyle(color: Colors.black38, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      return const SizedBox.shrink();
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (_maxDataPoints - 1).toDouble(),
          minY: 0,
          maxY: 100, 
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true, 
              color: _currentTemperature >= tempDangerMin 
                  ? Colors.red 
                  : (_currentTemperature >= tempWarnMin ? Colors.amber : Colors.blue),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true), 
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

  // 🔌 動態耗電狀態看板 UI (已補全中斷處並串接實時功率趨勢按鈕)
  Widget _buildPowerStatusPanel() {
    bool isWaste = _currentPowerState == 'waste';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), 
      decoration: BoxDecoration(
        color: isWaste ? const Color(0xFFFFF3E0) : const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isWaste ? const Color(0xFFD84315) : Colors.black26, 
          width: isWaste ? 2.0 : 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1️⃣ 上半部：插頭圖標與文字內容
          Row(
            crossAxisAlignment: CrossAxisAlignment.center, 
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.power, 
                    size: 38, 
                    color: isWaste ? const Color(0xFF424242) : Colors.green[600],
                  ),
                  if (isWaste)
                    const Positioned(
                      right: 0,
                      top: 0,
                      child: Icon(
                        Icons.volcano, 
                        size: 18, 
                        color: Color(0xFFFF3D00),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center, 
                  children: [
                    Text(
                      isWaste ? "💥 偵測到電力過度浪費！" : "🌱 用電量處於安全範圍",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isWaste ? const Color(0xFFD84315) : Colors.green[800],
                      ),
                    ),
                    const SizedBox(height: 4),
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
          
          const SizedBox(height: 16), 

          // 2️⃣ 下半部：橫跨整行的查看耗電趨勢按鈕 (2.5D 手繪描邊風格)
          InkWell(
            onTap: _showPowerChartBottomSheet,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(2, 2), 
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bolt_rounded, size: 16, color: Colors.amber),
                  SizedBox(width: 6),
                  Text(
                    '查看實時功率趨勢圖', 
                    style: TextStyle(fontSize: 13, color: Colors.black, fontWeight: FontWeight.bold)
                  ),
                ],
              ),
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
