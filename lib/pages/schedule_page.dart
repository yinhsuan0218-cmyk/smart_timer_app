import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/mqtt_service.dart';
import 'commonappbar.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SchedulePage extends StatefulWidget {
  final String zoneId;
  final String deviceId;
  final String deviceName;

  const SchedulePage({
    super.key, 
    required this.zoneId, 
    required this.deviceId, 
    required this.deviceName,
  });

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  List<bool> days = List.generate(7, (_) => false);
  TimeOfDay start = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay end = const TimeOfDay(hour: 22, minute: 0);
  bool isLoading = true; // 新增：用來顯示載入中的圈圈

  @override
  void initState() {
    super.initState();
    _loadExistingSchedule(); // ★ 頁面一打開，立刻去 Firebase 抓資料
  }

  // ★★★ 核心功能：從 Firebase 讀取該設備目前的排程記憶 ★★★
  Future<void> _loadExistingSchedule() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseDatabase.instance.ref('users/$uid/zones/${widget.zoneId}/devices/${widget.deviceId}');
    final snapshot = await ref.get();

    if (snapshot.exists && snapshot.value != null) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      
      setState(() {
        // 1. 讀取星期幾
        if (data['schedule_days'] != null) {
          List<dynamic> savedDays = data['schedule_days'];
          for (int i = 0; i < savedDays.length && i < 7; i++) {
            days[i] = savedDays[i] == true;
          }
        }

        // 2. 讀取開始時間 (例如 "18:30" 拆解成 18 和 30)
        if (data['timer_start'] != null && data['timer_start'].toString().isNotEmpty) {
          final parts = data['timer_start'].toString().split(':');
          if (parts.length == 2) {
            start = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
          }
        }

        // 3. 讀取結束時間
        if (data['timer_end'] != null && data['timer_end'].toString().isNotEmpty) {
          final parts = data['timer_end'].toString().split(':');
          if (parts.length == 2) {
            end = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
          }
        }
      });
    }
    
    // 讀取完畢，關閉載入動畫
    setState(() {
      isLoading = false;
    });
  }

  Future<void> pickTime({required bool isStart}) async {
    final initial = isStart ? start : end;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.black, onPrimary: Colors.white, onSurface: Colors.black),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) start = picked;
        else end = picked;
      });
    }
  }

  void sendSchedule() async {
    // 1. 基本防呆
    if (!days.contains(true)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請至少選擇一天')));
      return;
    }

    final int startMinutes = start.hour * 60 + start.minute;
    final int endMinutes = end.hour * 60 + end.minute;
    if (endMinutes <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ 結束時間必須晚於開始時間！')));
      return; 
    }

    // 2. 格式化時間
    final startStr = "${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}";
    final endStr = "${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}";

    setState(() => isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception("使用者未登入");

      // 3. 執行 Firebase 寫入
      final ref = FirebaseDatabase.instance.ref('users/$uid/zones/${widget.zoneId}/devices/${widget.deviceId}');
      
      // 注意：使用 await 確保 Firebase 寫入完成
      await ref.update({
        'timer_start': startStr,
        'timer_end': endStr,
        'schedule_days': days,
        'last_updated': DateTime.now().toIso8601String(),
      });

      // 4. 發送 MQTT (放入另一個 try 區塊，避免 MQTT 失敗影響到 UI 回饋)
      try {
        final schedule = {
          "device_id": widget.deviceId,
          "days": days,
          "start": startStr,
          "end": endStr,
        };
        MqttService().publish('smart_timer/schedule', jsonEncode(schedule));
      } catch (mqttError) {
        debugPrint("MQTT 發送失敗（硬體可能暫時無法接收），但雲端已儲存: $mqttError");
        // 這裡可以選擇不報錯，因為雲端已經存好了
      }

      // 5. 顯示成功彈窗
      if (!mounted) return;
      
      // 先關閉讀取狀態
      setState(() => isLoading = false);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('設定成功', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text('${widget.deviceName} 的排程已更新並同步至雲端。'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);     // 關閉彈窗
                Navigator.pop(context); // 回到首頁
              },
              child: const Text('我知道了', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

    } catch (e) {
      // 只有當 Firebase 寫入真的報錯時才會跑到這裡
      debugPrint("Firebase 儲存真正失敗: $e");
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗，請檢查網路連線: $e')),
        );
      }
    }
  }

  // ★★★ 新增：帶有確認對話框的取消功能 ★★★
  void cancelSchedule() async {
    // 顯示確認對話框
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確定取消排程？'),
        content: const Text('這將會移除本設備所有的每週循環任務。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('先不要')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('確定取消', style: TextStyle(color: Colors.redAccent))
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => isLoading = true); // 顯示讀取中

    try {
      // 1. 更新 UI 狀態
      setState(() {
        days = List.generate(7, (_) => false);
      });

      // 2. 更新 Firebase
      final ref = FirebaseDatabase.instance.ref('users/$uid/zones/${widget.zoneId}/devices/${widget.deviceId}');
      await ref.update({
        'schedule_days': days,
        'last_updated': DateTime.now().toIso8601String(),
      });

      // 3. 發送 MQTT 告知 ESP32
      final schedule = {
        "device_id": widget.deviceId,
        "days": days,
        "start": "",
        "end": "",
        "action": "cancel"
      };
      MqttService().publish('smart_timer/schedule', jsonEncode(schedule));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所有排程已取消'), backgroundColor: Colors.black)
      );
    } catch (e) {
      debugPrint("取消排程失敗: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CommonAppBar(showBackButton: true),
      // 如果正在讀取資料，畫面中間先轉圈圈
      body: isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.black))
        : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '設定 ${widget.deviceName}',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black, letterSpacing: 1.2),
            ),
            const SizedBox(height: 16),
            
            // 星期選擇區
            // ★ 升級版：星期選擇區 (絕對不會換行)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.black12),
              ),
              child: Row( // 改用 Row
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(7, (i) {
                  final dayLabels = ['一', '二', '三', '四', '五', '六', '日'];
                  bool isSelected = days[i];
                  return Expanded( // ★ 用 Expanded 讓 7 個按鈕平分寬度
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0), // 縮小按鈕之間的間距
                      child: ChoiceChip(
                        labelPadding: EdgeInsets.zero, // 消滅預設的左右留白
                        label: Center(child: Text(dayLabels[i])), // 讓字體乖乖置中
                        selected: isSelected,
                        onSelected: (v) => setState(() => days[i] = v),
                        selectedColor: Colors.black,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: isSelected ? Colors.black : Colors.black12),
                        ),
                        showCheckmark: false,
                      ),
                    ),
                  );
                }),
              ),
            ),
            
            const SizedBox(height: 32),
            const Text('運行時間段', style: TextStyle(color: Colors.black54, fontSize: 14)),
            const SizedBox(height: 16),

            _buildTimeTile(
              label: '開始時間',
              time: start.format(context),
              icon: Icons.access_time_filled_rounded,
              onTap: () => pickTime(isStart: true),
            ),
            const SizedBox(height: 16),
            _buildTimeTile(
              label: '結束時間',
              time: end.format(context),
              icon: Icons.history_toggle_off_rounded,
              onTap: () => pickTime(isStart: false),
            ),

            const SizedBox(height: 60),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: sendSchedule,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  elevation: 0,
                ),
                child: const Text('確認排程', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: cancelSchedule,
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: const Text('取消並關閉所有排程', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeTile({required String label, required String time, required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.black),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.black45)),
                Text(time, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black26),
          ],
        ),
      ),
    );
  }
}