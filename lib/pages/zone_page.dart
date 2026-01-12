import 'package:flutter/material.dart';
import '../models/zone.dart';
import 'service_page.dart';

class ZonePage extends StatefulWidget {
  const ZonePage({super.key});

  @override
  State<ZonePage> createState() => _ZonePageState();
}

class _ZonePageState extends State<ZonePage> {
  final List<Zone> zones = [];

  void addZone() {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增 Zone'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Zone name'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  zones.add(
                    Zone(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: name,
                    ),
                  );
                });
              }
              Navigator.pop(context);
            },
            child: const Text('新增'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: zones.length,
          itemBuilder: (context, index) {
            final zone = zones[index];
            return Dismissible(
              key: Key(zone.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (_) {
                setState(() => zones.removeAt(index));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${zone.name} 已刪除')),
                );
              },
              child: ListTile(
                title: Text(zone.name),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ServicePage(zone: zone),
                    ),
                  );
                },
              ),
            );
          },
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            tooltip: '新增 Zone',
            onPressed: addZone,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}
