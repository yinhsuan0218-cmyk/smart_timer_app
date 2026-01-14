import 'package:flutter/material.dart';
import 'schedule_page.dart';
import 'commonappbar.dart';

class HomePage extends StatefulWidget {
  // 1. 新增 showTutorial 參數，預設為 false
  final bool showTutorial;
  const HomePage({super.key, this.showTutorial = false});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String filter = '全部';

  @override
  void initState() {
    super.initState();
    // 2. 只有當 showTutorial 為 true 時，才執行彈窗邏輯
    if (widget.showTutorial) {
      Future.delayed(const Duration(seconds: 1), _showCompletionDialog);
    }
  }

  // 教學完成的最後彈窗 (保持不變)
  void _showCompletionDialog() {
    if (!context.mounted) return; // 確保 context 還在
    showDialog(
      context: context,
      barrierDismissible: false, // 教學完成建議強制點擊按鈕
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('🎉 恭喜完成教學！', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('您現在已經掌握了 Smart Timer 的所有核心操作。\n\n您可以在首頁查看裝置狀態，或點擊裝置右側的「行事曆」圖示查看詳細排程。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('開始體驗', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 模擬設備資料 (保持不變)
  final List<Map<String, dynamic>> devices = [
    {'name': '客廳燈光', 'status': '運作中', 'icon': Icons.lightbulb_outline_rounded},
    {'name': '臥室風扇', 'status': '未運作', 'icon': Icons.air_rounded},
    {'name': '廚房熱水器', 'status': '運作中', 'icon': Icons.whatshot_rounded},
    {'name': '書房插座', 'status': '未運作', 'icon': Icons.power_rounded},
  ];

  @override
  Widget build(BuildContext context) {
    final filteredDevices = filter == '全部'
        ? devices
        : devices.where((d) => d['status'] == filter).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
                'Home',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  letterSpacing: 1.2,
                ),
              ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
            child: Text(
              '管理您的智慧設備',
              style: TextStyle(fontSize: 14, color: Colors.black45, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 16),

          // 過濾標籤 (保持不變)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: ['全部', '運作中', '未運作'].map((category) {
                bool isSelected = filter == category;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => filter = category);
                    },
                    selectedColor: Colors.black,
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: isSelected ? Colors.black : Colors.black12),
                    ),
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // 設備清單 (保持不變)
          Expanded(
            child: filteredDevices.isEmpty 
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  physics: const BouncingScrollPhysics(),
                  itemCount: filteredDevices.length,
                  itemBuilder: (context, index) {
                    final device = filteredDevices[index];
                    final bool isRunning = device['status'] == '運作中';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.black12, width: 1),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isRunning ? Colors.black : Colors.grey[50],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            device['icon'], 
                            color: isRunning ? Colors.white : Colors.black,
                            size: 24,
                          ),
                        ),
                        title: Text(
                          device['name'], 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            device['status'], 
                            style: TextStyle(
                              color: isRunning ? Colors.green[700] : Colors.black26,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.calendar_today_rounded, size: 20),
                              color: Colors.black54,
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const SchedulePage()),
                                );
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.power_settings_new_rounded, 
                                color: isRunning ? Colors.black : Colors.black12,
                                size: 28,
                              ),
                              onPressed: () {},
                            ),
                          ],
                        ),
                      ),
                    );
                  },
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
          Icon(Icons.devices_other_rounded, size: 64, color: Colors.grey[200]),
          const SizedBox(height: 16),
          const Text('沒有找到對應的設備', style: TextStyle(color: Colors.black26)),
        ],
      ),
    );
  }
}