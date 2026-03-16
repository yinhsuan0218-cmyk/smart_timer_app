import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ★ 新增：引入 Auth
import 'schedule_page.dart'; // ★ 確保有這行
import '../services/mqtt_service.dart'; // ★ 確保路徑正確，引入你的 MQTT 服務

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
  String? uid; // ★ 新增用來存 UID
  final MqttService _mqttService = MqttService(); // ★ 初始化 MQTT 服務

  @override
  void initState() {
    super.initState();
    // ★ 抓取目前登入使用者的 UID
    uid = FirebaseAuth.instance.currentUser?.uid;
    // 連接 MQTT Broker
    _mqttService.connect();
    // ★ 關鍵修改：路徑變成 'users/你的UID/zones/區域ID/devices'
    if (uid != null) {
      _devicesRef = FirebaseDatabase.instance.ref('users/$uid/zones/${widget.zoneId}/devices');
    } else {
      // 防呆預設
      _devicesRef = FirebaseDatabase.instance.ref('zones/${widget.zoneId}/devices');
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

  // 新增裝置
  void addDevice() {
    final TextEditingController idController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增裝置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            //TextField(controller: nameController, decoration: const InputDecoration(labelText: '裝置名稱', hintText: '例如：吸頂燈')),
            TextField(controller: idController, decoration: const InputDecoration(labelText: '自訂 ID', hintText: '例如：light_01')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (idController.text.isNotEmpty) {
                // 寫入到該使用者的該區域底下
                _devicesRef.child(idController.text.trim()).set({
                  'is_active': false,
                  'timer_start': "",
                  'timer_end': "",
                });
                Navigator.pop(context);
              }
            },
            child: const Text('新增'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.zoneName), // 顯示 "客廳"
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

          if (deviceList.isEmpty) return const Center(child: Text("此區域尚無裝置"));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: deviceList.length,
            itemBuilder: (context, index) => _buildDeviceCard(deviceList[index]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addDevice,
        label: const Text('新增裝置'),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.white,
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
                      onChanged: (val) => _toggleDevice(id, val), // 調用此函式才會發送 MQTT
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