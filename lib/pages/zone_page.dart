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

  // 通用的教學指引彈窗
  void _showTutorialDialog({required String title, required String content}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("我知道了", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 新增區域的邏輯
  void addZone() {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('新增區域', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          cursorColor: Colors.black,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '例如：客廳',
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.black)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  zones.add(Zone(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: name,
                  ));
                });
                Navigator.pop(context); // 關閉輸入框

                // 教學引導：新增後的下一步
                _showTutorialDialog(
                  title: "區域建立成功！",
                  content: "接下來請「點選清單中的 $name」進入，來新增該區域的智慧設備（Service）。",
                );
              }
            },
            child: const Text('新增', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
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
        centerTitle: false,
        title: const Text(
          'Zone',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 28),
        ),
      ),
      body: Stack(
        children: [
          zones.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
                  itemCount: zones.length,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {
                    final zone = zones[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Dismissible(
                        key: Key(zone.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        ),
                        onDismissed: (_) {
                          setState(() => zones.removeAt(index));
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.black12, width: 1),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            leading: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.grid_view_rounded, color: Colors.black, size: 24),
                            ),
                            title: Text(
                              zone.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            subtitle: const Text('點擊管理設備', style: TextStyle(fontSize: 12, color: Colors.black26)),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black12),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ServicePage(zone: zone),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
          
          // 懸浮按鈕 (FAB)
          Positioned(
            bottom: 30,
            right: 24,
            child: FloatingActionButton.extended(
              elevation: 4,
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              onPressed: addZone,
              label: const Text('新增區域', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              icon: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.layers_outlined, size: 64, color: Colors.grey[200]),
          ),
          const SizedBox(height: 24),
          const Text('尚未建立任何區域', style: TextStyle(color: Colors.black26, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('點擊右下角按鈕開始', style: TextStyle(color: Colors.black12, fontSize: 14)),
        ],
      ),
    );
  }
}