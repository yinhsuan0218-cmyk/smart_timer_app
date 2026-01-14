import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/mqtt_service.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  List<bool> days = List.generate(7, (_) => false);
  TimeOfDay start = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay end = const TimeOfDay(hour: 22, minute: 0);

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

  void sendSchedule() {
    if (!days.contains(true)) {
      _showSnackBar('請至少選擇一天');
      return;
    }

    final schedule = {
      "days": days,
      "start": "${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}",
      "end": "${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}",
    };

    MqttService().publish('smart_timer/schedule', jsonEncode(schedule));
    _showSnackBar('排程已送出');
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Schedule', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 24)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('重複週期', style: TextStyle(color: Colors.black54, fontSize: 14)),
            const SizedBox(height: 16),
            
            // 星期選擇區
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.black12),
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: List.generate(7, (i) {
                  final dayLabels = ['一', '二', '三', '四', '五', '六', '日'];
                  bool isSelected = days[i];
                  return ChoiceChip(
                    label: Text(dayLabels[i]),
                    selected: isSelected,
                    onSelected: (v) => setState(() => days[i] = v),
                    selectedColor: Colors.black,
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(color: isSelected ? Colors.black : Colors.black12),
                    ),
                    showCheckmark: false,
                  );
                }),
              ),
            ),
            
            const SizedBox(height: 32),
            const Text('運行時間段', style: TextStyle(color: Colors.black54, fontSize: 14)),
            const SizedBox(height: 16),

            // 時間選擇卡片
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

            // 設定按鈕
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