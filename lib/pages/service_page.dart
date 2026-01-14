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

  // 教學專用彈窗
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

  void addService() {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('新增裝置', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          cursorColor: Colors.black,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '裝置名稱（例如：電燈）',
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
                  services.add(
                    Service(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: name,
                    ),
                  );
                });
                Navigator.pop(context); // 關閉輸入對話框

                // --- 教學指引：裝置建立成功 ---
                _showTutorialDialog(
                  title: "裝置已新增！",
                  content: "現在請「點擊清單中的 $name」來為它設定定時器 (Timer)。",
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${widget.zone.name} 裝置列表',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 22),
        ),
      ),
      body: Stack(
        children: [
          services.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
                  itemCount: services.length,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {
                    final service = services[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Dismissible(
                        key: Key(service.id),
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
                          setState(() => services.removeAt(index));
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
                              child: const Icon(Icons.settings_remote_rounded, color: Colors.black),
                            ),
                            title: Text(
                              service.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            subtitle: const Text('點擊設定定時任務', style: TextStyle(fontSize: 12, color: Colors.black26)),
                            trailing: const Icon(Icons.timer_outlined, color: Colors.black12, size: 20),
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
                        ),
                      ),
                    );
                  },
                ),
          
          // 懸浮按鈕
          Positioned(
            bottom: 30,
            right: 24,
            child: FloatingActionButton.extended(
              elevation: 4,
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              onPressed: addService,
              label: const Text('新增裝置', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            decoration: BoxDecoration(color: Colors.grey[50], shape: BoxShape.circle),
            child: Icon(Icons.developer_board_off_outlined, size: 64, color: Colors.grey[200]),
          ),
          const SizedBox(height: 24),
          Text('此區域尚無裝置', style: TextStyle(color: Colors.black26, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('點擊右下角按鈕新增設備', style: TextStyle(color: Colors.black12, fontSize: 14)),
        ],
      ),
    );
  }
}