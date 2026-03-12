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
  // ★ 新增的變數
  bool isRepeatMode = true; // true = 每週循環, false = 單次排程
  DateTime selectedDate = DateTime.now(); // 單次排程用的日期

  List<bool> days = List.generate(7, (_) => false);
  TimeOfDay start = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay end = const TimeOfDay(hour: 22, minute: 0);
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExistingSchedule();
  }

  Future<void> _loadExistingSchedule() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseDatabase.instance.ref('users/$uid/zones/${widget.zoneId}/devices/${widget.deviceId}');
    final snapshot = await ref.get();

    if (snapshot.exists && snapshot.value != null) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      
      setState(() {
        // ★ 1. 讀取排程模式 (如果是單次排程)
        if (data['schedule_mode'] == 'once') {
          isRepeatMode = false;
        } else {
          isRepeatMode = true;
        }

        // ★ 2. 讀取單次排程的日期
        if (data['schedule_date'] != null) {
          selectedDate = DateTime.tryParse(data['schedule_date']) ?? DateTime.now();
        }

        // 3. 讀取星期幾 (維持不變)
        if (data['schedule_days'] != null) {
          List<dynamic> savedDays = data['schedule_days'];
          for (int i = 0; i < savedDays.length && i < 7; i++) {
            days[i] = savedDays[i] == true;
          }
        }

        // 讀取時間 (維持原本的寫法)
        if (data['timer_start'] != null && data['timer_start'].toString().isNotEmpty) {
          final parts = data['timer_start'].toString().split(':');
          if (parts.length == 2) start = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
        if (data['timer_end'] != null && data['timer_end'].toString().isNotEmpty) {
          final parts = data['timer_end'].toString().split(':');
          if (parts.length == 2) end = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
      });
    }
    setState(() => isLoading = false);
  }

  // ★ 新增：選擇日期的功能
  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now(), // 不能選過去的時間
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.black, onSurface: Colors.black),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  // ... 底下的 pickTime 維持不變

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
    // 1. 防呆檢查：依照模式不同有不同的檢查
    if (isRepeatMode && !days.contains(true)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('循環排程請至少選擇一天')));
      return;
    }

    final int startMinutes = start.hour * 60 + start.minute;
    final int endMinutes = end.hour * 60 + end.minute;
    if (endMinutes <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ 結束時間必須晚於開始時間！')));
      return; 
    }

    // 2. 格式化時間與日期
    final startStr = "${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}";
    final endStr = "${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}";
    final dateStr = "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}";

    setState(() => isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception("使用者未登入");

      final ref = FirebaseDatabase.instance.ref('users/$uid/zones/${widget.zoneId}/devices/${widget.deviceId}');
      
      // ★ 3. 準備發送給硬體的 MQTT 封包 (區分模式)
      final Map<String, dynamic> schedulePayload = {
        "device_id": widget.deviceId,
        "mode": isRepeatMode ? "repeat" : "once", // 告知硬體這是哪種模式
        "start": startStr,
        "end": endStr,
      };

      if (isRepeatMode) {
        schedulePayload["days"] = days; // 循環模式傳送布林值陣列
      } else {
        schedulePayload["date"] = dateStr; // 單次模式傳送日期字串
      }

      // 4. 執行 Firebase 更新
      await ref.update({
        'timer_start': startStr,
        'timer_end': endStr,
        'schedule_mode': isRepeatMode ? 'repeat' : 'once',
        'schedule_days': isRepeatMode ? days : null, // 不是循環就清空
        'schedule_date': isRepeatMode ? null : dateStr, // 不是單次就清空
        'last_updated': DateTime.now().toIso8601String(),
      });

      // 5. 發送 MQTT
      MqttService().publish('smart_timer/schedule', jsonEncode(schedulePayload));

      if (!mounted) return;
      setState(() => isLoading = false);

      // (這裏接續你原本的 showDialog 成功彈窗邏輯...)
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
          content: Text('${widget.deviceName} 的排程已更新並同步。'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('我知道了', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

    } catch (e) {
      debugPrint("儲存失敗: $e");
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('儲存失敗: $e')));
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

      // 2. 更新 Firebase (★ 徹底清空所有排程欄位)
      final ref = FirebaseDatabase.instance.ref('users/$uid/zones/${widget.zoneId}/devices/${widget.deviceId}');
      await ref.update({
        'timer_start': "",       // 清空開始時間
        'timer_end': "",         // 清空結束時間
        'schedule_mode': null,   // 移除模式
        'schedule_days': null,   // 移除循環天數
        'schedule_date': null,   // 移除單次日期
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
            const SizedBox(height: 24),
            
            // ★ 新增：超有質感的模式切換開關
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => isRepeatMode = true),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isRepeatMode ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: isRepeatMode ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : null,
                        ),
                        child: Text('每週循環', style: TextStyle(fontWeight: FontWeight.bold, color: isRepeatMode ? Colors.black : Colors.black54)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => isRepeatMode = false),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !isRepeatMode ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: !isRepeatMode ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : null,
                        ),
                        child: Text('單次特定時間', style: TextStyle(fontWeight: FontWeight.bold, color: !isRepeatMode ? Colors.black : Colors.black54)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ★ 根據模式顯示不同的 UI
            // ★ 根據模式顯示不同的 UI
            if (isRepeatMode) ...[
              const Text('重複日期', style: TextStyle(color: Colors.black54, fontSize: 14)),
              const SizedBox(height: 8),
              
              // ★ 把不見的星期選擇補回來！
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(7, (i) {
                    final dayLabels = ['一', '二', '三', '四', '五', '六', '日'];
                    bool isSelected = days[i];
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.0),
                        child: ChoiceChip(
                          labelPadding: EdgeInsets.zero,
                          label: Center(child: Text(dayLabels[i])),
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
            ] else ...[
              const Text('指定日期', style: TextStyle(color: Colors.black54, fontSize: 14)),
              // ... 下面維持原本的 _buildTimeTile ...
              _buildTimeTile(
                label: '選擇日期',
                time: "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}",
                icon: Icons.calendar_month_rounded,
                onTap: _pickDate,
              ),
            ],
            
            const SizedBox(height: 32),
            const Text('運行時間段', style: TextStyle(color: Colors.black54, fontSize: 14)),
            const SizedBox(height: 16),
            // ... 底下接你原本的 開始時間、結束時間、按鈕 ...

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