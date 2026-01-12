import 'package:flutter/material.dart';
import '../models/zone.dart';
import '../models/service.dart';
import 'timer_page.dart';

class ServicePage extends StatefulWidget {
  final Zone zone;

  const ServicePage({super.key, required this.zone});

  @override
  State<ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends State<ServicePage> {
  final List<Service> services = [];

  void addService() {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增裝置'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Service name'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  services.add(
                    Service(
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.zone.name)),
      floatingActionButton: FloatingActionButton(
        tooltip: '新增裝置',
        onPressed: addService,
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        itemCount: services.length,
        itemBuilder: (context, index) {
          final service = services[index];
          return Dismissible(
            key: Key(service.id),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) {
              setState(() => services.removeAt(index));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${service.name} 已刪除')),
              );
            },
            child: ListTile(
              title: Text(service.name),
              trailing: const Icon(Icons.timer),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TimerPage(
                      zone: widget.zone,
                      service: service,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
