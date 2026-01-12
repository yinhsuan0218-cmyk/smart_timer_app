import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String filter = '全部';

  // 模擬設備清單
  final List<Map<String, dynamic>> devices = [
    {'name': 'Living Room - Lamp', 'status': '運作中'},
    {'name': 'Bedroom - Fan', 'status': '未運作'},
    {'name': 'Kitchen - Heater', 'status': '運作中'},
  ];

  @override
  Widget build(BuildContext context) {
    // 根據 filter 過濾清單
    final filteredDevices = filter == '全部'
        ? devices
        : devices.where((d) => d['status'] == filter).toList();

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          DropdownButton<String>(
            value: filter,
            items: ['全部', '運作中', '未運作']
                .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(e),
                    ))
                .toList(),
            onChanged: (v) => setState(() => filter = v!),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: filteredDevices.length,
              itemBuilder: (_, index) {
                final device = filteredDevices[index];
                return ListTile(
                  title: Text(device['name']),
                  trailing: Icon(
                    Icons.power_settings_new,
                    color: device['status'] == '運作中'
                        ? Colors.green
                        : Colors.red,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
