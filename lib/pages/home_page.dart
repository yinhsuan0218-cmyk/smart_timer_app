import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart'; // 務必確認有這行
import 'schedule_page.dart';
import 'commonappbar.dart';

class HomePage extends StatefulWidget {
  final bool showTutorial;
  const HomePage({super.key, this.showTutorial = false});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String filter = '全部';

  // 【修正 1】將原本的 _devicesRef 改為 _zonesRef，因為你的資料在 zones 節點下
  final DatabaseReference _zonesRef = FirebaseDatabase.instance.ref('zones');

  @override
  void initState() {
    super.initState();
    if (widget.showTutorial) {
      Future.delayed(const Duration(seconds: 1), _showCompletionDialog);
    }
  }

  void _showCompletionDialog() {
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('🎉 恭喜完成教學！', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('您現在已經掌握了 Smart Timer 的所有核心操作。\n\n您可以在首頁查看裝置狀態，或點擊裝置右側的「行事曆」圖示查看詳細排程。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('開始體驗', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 根據後端 type 字串顯示圖示
  IconData _getIconData(String? type) {
    switch (type) {
      case 'light': return Icons.lightbulb_outline_rounded;
      case 'fan': return Icons.air_rounded;
      case 'heater': return Icons.whatshot_rounded;
      default: return Icons.power_rounded;
    }
  }

  // 【修正 2】更新狀態的方法，確保使用正確的 _zonesRef
  void _toggleDevice(String zoneId, String deviceId, bool currentStatus) {
  // 這裡會將後端的 status 改為與目前相反的值
      _zonesRef.child('$zoneId/devices/$deviceId').update({
        'is_active': !currentStatus,
      });
    }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題部分
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 60, 24, 0),
            child: Text(
              'Home',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
            child: Text('管理您的智慧設備', style: TextStyle(fontSize: 14, color: Colors.black45)),
          ),

          // 篩選標籤
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: ['全部', '運作中', '未運作'].map((category) {
                bool isSelected = filter == category;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => filter = category);
                    },
                    selectedColor: Colors.black,
                    labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
                    showCheckmark: false,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // 3. 重點：使用 StreamBuilder 取代原本的 ListView
          Expanded(
            child: StreamBuilder(
              stream: _zonesRef.onValue, // 監聽整個 zones 節點
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text("連線錯誤"));
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.black));
                }

                List<Map<String, dynamic>> allDevices = [];

                if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                  // 【修正 3】解析資料時增加型別檢查，避免 runtime error
                  final zonesData = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);

                  zonesData.forEach((zoneId, zoneValue) {
                    final zoneMap = Map<dynamic, dynamic>.from(zoneValue as Map);
                    
                    if (zoneMap.containsKey('devices')) {
                      final devicesMap = Map<dynamic, dynamic>.from(zoneMap['devices'] as Map);
                      
                      devicesMap.forEach((deviceId, deviceValue) {
                        final device = Map<String, dynamic>.from(deviceValue as Map);
                        device['id'] = deviceId;
                        device['zoneId'] = zoneId; 
                        device['zoneName'] = zoneMap['name']; 

                        // 篩選邏輯
                        bool isRunning = device['is_active'] == true;
                        if (filter == '全部') {
                          allDevices.add(device);
                        } else if (filter == '運作中' && isRunning) {
                          allDevices.add(device);
                        } else if (filter == '未運作' && !isRunning) {
                          allDevices.add(device);
                        }
                      });
                    }
                  });
                }

                if (allDevices.isEmpty) return _buildEmptyState();

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: allDevices.length,
                  itemBuilder: (context, index) {
                    final dev = allDevices[index];
                    final bool isRunning = dev['is_active'] ?? false;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            // 開啟時背景變黑，關閉時接近白色
                            color: isRunning ? Colors.black : Colors.grey[100], 
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _getIconData(dev['type']),
                            // 開啟時圖示變白，關閉時圖示黑色
                            color: isRunning ? Colors.white : Colors.black,
                          ),
                        ),
                        title: Text(dev['name'] ?? '未知設備', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${dev['zoneName']} - ${isRunning ? '運作中' : '未運作'}', 
                                      style: TextStyle(color: isRunning ? Colors.green : Colors.black26)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.calendar_today_rounded),
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SchedulePage())),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.power_settings_new_rounded, 
                                // 當 isRunning 為 true (開啟) 時顯示黑色，false (關閉) 時顯示淺灰色
                                color: isRunning ? Colors.black : Colors.black12, 
                                size: 28,
                              ),
                              onPressed: () => _toggleDevice(dev['zoneId'], dev['id'], isRunning),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.devices_other_rounded, size: 64, color: Colors.grey[200]),
          const SizedBox(height: 16),
          const Text('沒有找到對應的設備', style: TextStyle(color: Colors.black26)),
        ],
      ),
    );
  }
}