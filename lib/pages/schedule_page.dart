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

  // 選擇時間
  Future<void> pickTime({required bool isStart}) async {
    final initial = isStart ? start : end;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少選擇一天')),
      );
      return;
    }

    final schedule = {
      "days": days,
      "start": "${start.hour.toString().padLeft(2,'0')}:${start.minute.toString().padLeft(2,'0')}",
      "end": "${end.hour.toString().padLeft(2,'0')}:${end.minute.toString().padLeft(2,'0')}",
    };

    // 使用 JSON 發送，比 toString() 好
    MqttService().publish('smart_timer/schedule', jsonEncode(schedule));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('排程已送出')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            children: List.generate(7, (i) {
              return ChoiceChip(
                label: Text(['一','二','三','四','五','六','日'][i]),
                selected: days[i],
                onSelected: (v) => setState(() => days[i] = v),
              );
            }),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ElevatedButton(
                onPressed: () => pickTime(isStart: true),
                child: Text('開始: ${start.format(context)}'),
              ),
              ElevatedButton(
                onPressed: () => pickTime(isStart: false),
                child: Text('結束: ${end.format(context)}'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: sendSchedule,
            child: const Text('Set'),
          )
        ],
      ),
    );
  }
}
