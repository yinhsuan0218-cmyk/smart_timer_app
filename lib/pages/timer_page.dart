import 'package:flutter/material.dart';
import '../models/zone.dart';
import '../models/service.dart';
import '../services/mqtt_service.dart';
import 'commonappbar.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';

class TimerPage extends StatefulWidget {
  final Zone zone;
  final Service service;

  const TimerPage({super.key, required this.zone, required this.service});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  DateTime? start;
  DateTime? end;

  // 1. 選擇日期與時間的邏輯
  Future<void> pickDateTime(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      builder: (context, child) => _buildPickerTheme(child!),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) => _buildPickerTheme(child!),
    );
    if (time == null) return;

    final result = DateTime(
      date.year, date.month, date.day, time.hour, time.minute,
    );

    setState(() {
      if (isStart) start = result;
      else end = result;
    });
  }

  // 統一選擇器的黑白主題
  Widget _buildPickerTheme(Widget child) {
    return Theme(
      data: ThemeData.light().copyWith(
        colorScheme: const ColorScheme.light(
          primary: Colors.black, 
          onPrimary: Colors.white,
          onSurface: Colors.black,
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: Colors.black),
        ),
      ),
      child: child,
    );
  }

  String formatDateTime(DateTime? dt) {
    if (dt == null) return '尚未設定';
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} "
           "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  void sendTimer() async {
    if (start == null || end == null) {
      _showToast('請先設定開始與結束時間');
      return;
    }
    if (end!.isBefore(start!)) {
      _showToast('結束時間不能早於開始時間');
      return;
    }

    // ★★★ 核心邏輯：判定現在是否在排程時段內 ★★★
    final now = DateTime.now();
    // 如果「現在時間」在「開始」之後，且在「結束」之前
    bool shouldBeActiveNow = now.isAfter(start!) && now.isBefore(end!);

    final startStr = formatDateTime(start);
    final endStr = formatDateTime(end);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // 1. 取得 Firebase 參照 
      // 注意：這裡假設 widget.service 有 id 屬性。如果沒有，請根據你的 model 調整
      final ref = FirebaseDatabase.instance.ref('users/$uid/zones/${widget.zone.id}/devices/${widget.service.id}');

      // 2. 更新 Firebase：同步寫入 timer 和 is_active
      await ref.update({
        'timer_start': startStr,
        'timer_end': endStr,
        'is_active': shouldBeActiveNow, // ★ 同步狀態
        'schedule_days': null,          // ★ 確保清除掉週期性排程，改為一次性計時
        'last_updated': DateTime.now().toIso8601String(),
      });

      // 3. 執行 MQTT 發送（發送給硬體）
      final payload = {
        "device_id": widget.service.id,
        "start": startStr,
        "end": endStr,
        "is_active": shouldBeActiveNow,
      };
      MqttService().publish('smart_timer/timer', jsonEncode(payload));
      
      // 4. 教學彈窗 (保持你原本的代碼)
      if (!mounted) return;
      _showSuccessDialog();

    } catch (e) {
      _showToast('設定失敗：$e');
    }
  }

  // 將彈窗邏輯抽離，保持 sendTimer 整潔
  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.black, size: 28),
            SizedBox(width: 12),
            Text('設定成功！', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          '您的單次排程已送出。教學最後一步：請點擊下方導覽列中間的「Home」回到首頁，確認裝置的運行狀態。',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); 
              Navigator.pop(context); 
            },
            child: const Text('完成教學', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CommonAppBar(showBackButton: false),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Timer Setup',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  letterSpacing: 1.2,
                ),
              ),
            const Text('設定自動運行時段', style: TextStyle(color: Colors.black38, fontSize: 14)),
            const SizedBox(height: 32),
            
            _buildTimeTile(
              title: '開始時間',
              value: formatDateTime(start),
              icon: Icons.play_arrow_rounded,
              onTap: () => pickDateTime(true),
              isActive: start != null,
            ),
            
            const SizedBox(height: 20),
            
            _buildTimeTile(
              title: '結束時間',
              value: formatDateTime(end),
              icon: Icons.stop_rounded,
              onTap: () => pickDateTime(false),
              isActive: end != null,
            ),
            
            const Spacer(),
            
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      side: const BorderSide(color: Colors.black12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('取消', style: TextStyle(color: Colors.black54)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: sendTimer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('確認設定', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeTile({
    required String title,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
    required bool isActive,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActive ? Colors.black : Colors.black12, 
            width: isActive ? 1.5 : 1,
          ),
          boxShadow: isActive ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))] : [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isActive ? Colors.black : Colors.grey[50],
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: isActive ? Colors.white : Colors.black26, size: 24),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, color: Colors.black38)),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.black : Colors.black12,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(Icons.edit_calendar_outlined, size: 18, color: isActive ? Colors.black26 : Colors.black12),
          ],
        ),
      ),
    );
  }
}