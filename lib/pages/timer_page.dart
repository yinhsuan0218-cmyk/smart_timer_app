import 'package:flutter/material.dart';
import '../models/zone.dart';
import '../models/service.dart';
import '../services/mqtt_service.dart'; // 假設你有這個服務

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

  Future<void> pickDateTime(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;

    final result = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      if (isStart) start = result;
      else end = result;
    });
  }

  String formatDateTime(DateTime? dt) {
    if (dt == null) return '';
    return "${dt.year.toString().padLeft(4,'0')}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')} "
        "${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}";
  }

  void sendTimer() {
    if (start == null || end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先設定開始與結束時間')),
      );
      return;
    }

    if (end!.isBefore(start!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('結束時間不能早於開始時間')),
      );
      return;
    }

    final payload = {
      "zone": widget.zone.name,
      "service": widget.service.name,
      "start": formatDateTime(start),
      "end": formatDateTime(end),
    };

    // 模擬 MQTT 發送
    MqttService().publish('smart_timer/timer', payload.toString());

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('定時設定已送出')),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.service.name} 定時')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(start == null
                  ? '設定開始時間'
                  : '開始：${formatDateTime(start)}'),
              onTap: () => pickDateTime(true),
            ),
            ListTile(
              leading: const Icon(Icons.stop),
              title: Text(end == null
                  ? '設定結束時間'
                  : '結束：${formatDateTime(end)}'),
              onTap: () => pickDateTime(false),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: sendTimer,
                  child: const Text('Set'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
