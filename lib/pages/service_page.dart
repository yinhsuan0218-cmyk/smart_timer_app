import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class ServicePage extends StatefulWidget {
  final String zoneId;   // 知道是哪個區域 (例如 zone_01)
  final String zoneName; // 知道區域名字 (例如 客廳)

  const ServicePage({super.key, required this.zoneId, required this.zoneName});

  @override
  State<ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends State<ServicePage> {
  late DatabaseReference _devicesRef; // 改叫 devicesRef 比較貼切

  @override
  void initState() {
    super.initState();
    // ★★★ 關鍵修改：路徑變成 'zones/區域ID/devices' ★★★
    _devicesRef = FirebaseDatabase.instance.ref('zones/${widget.zoneId}/devices');
  }

  // 輔助函式：時間格式化
  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // 新增裝置
  void addDevice() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController idController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增裝置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: '裝置名稱', hintText: '例如：吸頂燈')),
            TextField(controller: idController, decoration: const InputDecoration(labelText: '自訂 ID', hintText: '例如：light_01')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && idController.text.isNotEmpty) {
                // 寫入到該區域底下
                _devicesRef.child(idController.text.trim()).set({
                  'name': nameController.text.trim(),
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

  // 時間選擇器
  Future<String?> _pickDateTime() async {
    final DateTime? date = await showDatePicker(
      context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2030),
    );
    if (date == null) return null;
    
    if (!mounted) return null;
    final TimeOfDay? time = await showTimePicker(
      context: context, initialTime: TimeOfDay.now(),
    );
    if (time == null) return null;

    final DateTime fullDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    return _formatDateTime(fullDateTime);
  }

  // 排程設定彈窗
  void _showScheduleDialog(String id, String currentStart, String currentEnd) {
    String tempStart = currentStart;
    String tempEnd = currentEnd;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('設定排程'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text("開始時間"),
                    subtitle: Text(tempStart.isEmpty ? "未設定" : tempStart),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      String? res = await _pickDateTime();
                      if (res != null) setStateDialog(() => tempStart = res);
                    },
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text("結束時間"),
                    subtitle: Text(tempEnd.isEmpty ? "未設定" : tempEnd),
                    trailing: const Icon(Icons.event_busy),
                    onTap: () async {
                      String? res = await _pickDateTime();
                      if (res != null) setStateDialog(() => tempEnd = res);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _devicesRef.child(id).update({'timer_start': "", 'timer_end': ""});
                    Navigator.pop(context);
                  },
                  child: const Text('清除', style: TextStyle(color: Colors.red)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (tempStart.isEmpty || tempEnd.isEmpty) return;
                    if (tempEnd.compareTo(tempStart) <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('結束時間必須晚於開始時間')));
                      return;
                    }
                    _devicesRef.child(id).update({'timer_start': tempStart, 'timer_end': tempEnd});
                    Navigator.pop(context);
                  },
                  child: const Text('儲存'),
                ),
              ],
            );
          },
        );
      },
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

  // 裝置卡片 UI (跟之前一模一樣)
  Widget _buildDeviceCard(Map<String, dynamic> device) {
    String name = device['name'] ?? '未命名';
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
            title: Text('刪除 $name?'), content: const Text('確定移除嗎？'),
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
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(isActive ? "開啟中" : "已關閉"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.date_range, color: hasSchedule ? Colors.blue : Colors.grey[300]),
                      onPressed: () => _showScheduleDialog(id, start, end),
                    ),
                    Switch(
                      value: isActive,
                      activeColor: Colors.black,
                      onChanged: (val) => _devicesRef.child(id).update({'is_active': val}),
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