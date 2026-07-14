import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WeeklySchedulePage extends StatefulWidget {
  const WeeklySchedulePage({super.key});

  @override
  State<WeeklySchedulePage> createState() => _WeeklySchedulePageState();
}

class _WeeklySchedulePageState extends State<WeeklySchedulePage> {
  late DatabaseReference _zonesRef;
  String? uid;

  // 星期標籤與對應的中文（從週一到週日，索引 0~6）
  final List<String> _dayLabels = ['週一', '週二', '週三', '週四', '週五', '週六', '週日'];

  @override
  void initState() {
    super.initState();
    // 取得 Firebase 路徑
    uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _zonesRef = FirebaseDatabase.instance.ref('users/$uid/zones');
    } else {
      _zonesRef = FirebaseDatabase.instance.ref('zones');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 獲取今天星期幾 (DateTime.now().weekday: 1 代表週一, 7 代表週日)
    final int currentWeekday = DateTime.now().weekday;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '一週課表總覽',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: StreamBuilder(
        stream: _zonesRef.onValue,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("連線錯誤"));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.black));
          }

          // 儲存所有設備
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
                  device['zoneName'] = zoneMap['name'] ?? '未命名區域';
                  allDevices.add(device);
                });
              }
            });
          }

          // 使用可橫向滾動的 SingleChildScrollView 呈現課表欄位
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(7, (index) {
                final int dayTarget = index + 1; // 1~7 對應 週一~週日
                final bool isToday = currentWeekday == dayTarget; // 是否為今天

                // 過濾出該天有排程的設備
                final dayDevices = allDevices.where((dev) {
                  final days = dev['schedule_days'] as List<dynamic>?;
                  if (days != null && days.length >= 7) {
                    return days[index] == true;
                  }
                  if (dev['schedule'] != null) {
                    final scheduleMap = Map<dynamic, dynamic>.from(dev['schedule'] as Map);
                    final weekdays = scheduleMap['weekdays'] as List<dynamic>?;
                    if (weekdays != null && weekdays.length >= 7) {
                      return weekdays[index] == true;
                    }
                  }
                  return false;
                }).toList();

                // 根據時間排序，讓課表從早到晚排列
                dayDevices.sort((a, b) {
                  String timeA = a['timer_start'] ?? a['schedule']?['start'] ?? '00:00';
                  String timeB = b['timer_start'] ?? b['schedule']?['start'] ?? '00:00';
                  return timeA.compareTo(timeB);
                });

                // 每一欄（天）的寬度固定為 160，方便橫向對齊與滾動
                return Container(
                  width: 165,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    // 如果是今天，背景加深或使用純白，並加上突出的邊框與陰影
                    color: isToday ? Colors.white : Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isToday ? Colors.black : Colors.black12,
                      width: isToday ? 2.5 : 1,
                    ),
                    boxShadow: isToday
                        ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 頂部星期標頭區
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          // 今天用黑底白字，平常日用透明
                          color: isToday ? Colors.black : Colors.transparent,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(isToday ? 17 : 19),
                            topRight: Radius.circular(isToday ? 17 : 19),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _dayLabels[index],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isToday ? Colors.white : Colors.black,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (isToday) ...[
                              const SizedBox(height: 2),
                              const Text(
                                'TODAY',
                                style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                              ),
                            ]
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Colors.black12),
                      
                      // 設備課表卡片清單
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: dayDevices.isEmpty
                            ? _buildEmptyColumnState()
                            : Column(
                                children: dayDevices.map((dev) {
                                  String startTime = dev['timer_start'] ?? dev['schedule']?['start'] ?? '--:--';
                                  String endTime = dev['timer_end'] ?? dev['schedule']?['end'] ?? '--:--';
                                  bool isRunning = dev['is_active'] == true;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      // 運作中的設備卡片背景變微綠或微灰
                                      color: isRunning ? Colors.green[50] : Colors.grey[50],
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isRunning ? Colors.green.withOpacity(0.3) : Colors.black12,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 時間範圍
                                        Row(
                                          children: [
                                            Icon(Icons.access_time_filled_rounded, size: 12, color: isRunning ? Colors.green : Colors.black45),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                '$startTime-$endTime',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: isRunning ? Colors.green[800] : Colors.black87,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        // 設備名稱
                                        Text(
                                          dev['id'] ?? '未知設備',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                        // 區域名稱
                                        Text(
                                          dev['zoneName'],
                                          style: const TextStyle(fontSize: 11, color: Colors.black38),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }

  // 當天沒有任何排程時的課表填空狀態
  Widget _buildEmptyColumnState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center, // 修正這裡
        children: [
          Icon(Icons.nights_stay_rounded, size: 28, color: Colors.black12),
          SizedBox(height: 8),
          Text(
            '無排程',
            style: TextStyle(color: Colors.black26, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
