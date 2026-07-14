import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WeeklySchedulePage extends StatefulWidget {
  const WeeklySchedulePage({super.key});

  @override
  State<WeeklySchedulePage> createState() => _WeeklySchedulePageState();
}

// 使用 SingleTickerProviderStateMixin 來驅動 7 天的 TabController
class _WeeklySchedulePageState extends State<WeeklySchedulePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DatabaseReference _zonesRef;
  String? uid;

  // 星期標籤與對應的中文
  final List<String> _dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    // 初始化 TabController，共 7 天
    _tabController = TabController(length: 7, vsync: this);

    // 取得 Firebase 路徑（與 HomePage 一致）
    uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _zonesRef = FirebaseDatabase.instance.ref('users/$uid/zones');
    } else {
      _zonesRef = FirebaseDatabase.instance.ref('zones');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '一週排程總覽',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          indicatorColor: Colors.black,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black26,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          indicatorSize: TabBarIndicatorSize.label,
          tabs: _dayLabels.map((day) => Tab(text: day)).toList(),
        ),
      ),
      body: StreamBuilder(
        stream: _zonesRef.onValue,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("連線錯誤"));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.black));
          }

          // 儲存從 Firebase 解析出來的所有設備
          List<Map<String, dynamic>> allDevices = [];

          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            final zonesData = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);

            zonesData.forEach((zoneId, zoneValue) {
              final zoneMap = Map<dynamic, dynamic>.from(zoneValue as Map);

              if (zoneMap.containsKey('devices')) {
                final devicesMap = Map<dynamic, dynamic>.from(zoneMap['devices'] as Map);

                devicesMap.forEach((deviceId, deviceValue) {
                  final device = Map<String, dynamic>.from(deviceValue as Map);
                  device['id'] = deviceId;
                  device['zoneId'] = zoneId;
                  device['zoneName'] = zoneMap['name'] ?? '未命名區域';
                  allDevices.add(device);
                });
              }
            });
          }

          // 使用 TabBarView 呈現 7 天的列表
          return TabBarView(
            controller: _tabController,
            children: List.generate(7, (dayIndex) {
              // 過濾出「當天有排程」的設備
              // dayIndex 0 代表星期一，對應 schedule_days[0]
              final dayDevices = allDevices.where((dev) {
                // 1. 循環排程模式 (對應你原有的 schedule_days 陣列結構)
                final days = dev['schedule_days'] as List<dynamic>?;
                if (days != null && days.length >= 7) {
                  return days[dayIndex] == true;
                }
                
                // 2. 如果你的結構改用了獨立的 Schedule Object (weekdays 欄位)
                if (dev['schedule'] != null) {
                  final scheduleMap = Map<dynamic, dynamic>.from(dev['schedule'] as Map);
                  final weekdays = scheduleMap['weekdays'] as List<dynamic>?;
                  if (weekdays != null && weekdays.length >= 7) {
                    return weekdays[dayIndex] == true;
                  }
                }
                return false;
              }).toList();

              // 如果當天沒有任何設備有排程
              if (dayDevices.isEmpty) {
                return _buildEmptyState(_dayLabels[dayIndex]);
              }

              // 當天的排程清單
              return ListView.builder(
                padding: const EdgeInsets.all(24),
                itemCount: dayDevices.length,
                itemBuilder: (context, index) {
                  final dev = dayDevices[index];
                  
                  // 兼容處理時間字串欄位
                  String startTime = dev['timer_start'] ?? dev['schedule']?['start'] ?? '--:--';
                  String endTime = dev['timer_end'] ?? dev['schedule']?['end'] ?? '--:--';
                  bool isRunning = dev['is_active'] == true;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          // 左側時間與圖示區
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isRunning ? Colors.black : Colors.grey[100],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _getIconData(dev['type']),
                              color: isRunning ? Colors.white : Colors.black,
                            ),
                          ),
                          const SizedBox(width: 16),
                          
                          // 中間設備與區域資訊
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dev['id'] ?? '未知設備',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  dev['zoneName'],
                                  style: const TextStyle(color: Colors.black45, fontSize: 13),
                                ),
                              ],
                            ),
                          ),

                          // 右側排程時間區
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$startTime - $endTime',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isRunning ? Colors.green.withOpacity(0.1) : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isRunning ? '運作中' : '待機中',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isRunning ? Colors.green : Colors.black45,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          );
        },
      ),
    );
  }

  // 根據設備類型顯示對應圖示（與你的 HomePage 一致）
  IconData _getIconData(String? type) {
    switch (type) {
      case 'light': return Icons.lightbulb_outline_rounded;
      case 'fan': return Icons.air_rounded;
      case 'heater': return Icons.whatshot_rounded;
      default: return Icons.power_rounded;
    }
  }

  // 當天無排程的空白狀態
  Widget _buildEmptyState(String day) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today_rounded, size: 64, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Text('星期$day 沒有安排任何自動化排程', style: const TextStyle(color: Colors.black26)),
        ],
      ),
    );
  }
}
