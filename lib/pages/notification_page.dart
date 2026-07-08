import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  Query? _notificationQuery;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _setupNotificationQuery();
  }

  void _setupNotificationQuery() {
    _uid = FirebaseAuth.instance.currentUser?.uid;
    if (_uid != null) {
      // 依照時間戳（key）排序，最新收到的高溫通知顯示在最上方
      _notificationQuery = FirebaseDatabase.instance
          .ref('users/$_uid/notifications')
          .orderByKey();
    }
  }

  void _clearAllNotifications() {
    if (_uid == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text("清除紀錄", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text("確定要清空所有的通知與溫度警報紀錄嗎？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseDatabase.instance.ref('users/$_uid/notifications').remove();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text("清空", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
        title: const Text("系統通知", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            onPressed: _clearAllNotifications,
            tooltip: "清空紀錄",
          )
        ],
      ),
      body: _uid == null
          ? const Center(child: Text("請先登入帳戶"))
          : StreamBuilder(
              stream: _notificationQuery?.onValue,
              builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.black));
                }

                if (snapshot.hasError || !snapshot.hasData || snapshot.data?.snapshot.value == null) {
                  return _buildEmptyState();
                }

                final Map<dynamic, dynamic> rawData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                
                // 轉為 List 並反轉（讓最新通知在最上面）
                final List<MapEntry<dynamic, dynamic>> sortedList = rawData.entries.toList()
                  ..sort((a, b) => b.key.compareTo(a.key));

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  itemCount: sortedList.length,
                  separatorBuilder: (context, index) => const Divider(color: Colors.black12, height: 1),
                  itemBuilder: (context, index) {
                    final item = Map<String, dynamic>.from(sortedList[index].value as Map);
                    final String notificationId = sortedList[index].key;

                    final String title = item['title'] ?? '系統提示';
                    final String content = item['content'] ?? '設備狀態已更新';
                    final String timeStr = item['timestamp'] ?? '';
                    final String type = item['type'] ?? 'info'; // 'danger', 'warn', 'info'

                    return _buildNotificationItem(
                      notificationId: notificationId,
                      title: title,
                      content: content,
                      timeStr: timeStr,
                      type: type,
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text("目前沒有任何通知紀錄", style: TextStyle(color: Colors.black38, fontSize: 16)),
        ],
      ),
    );
  }

  // 核心微調：根據不同的警報等級（danger / warn / info）渲染不同的卡片 UI
  Widget _buildNotificationItem({
    required String notificationId,
    required String title,
    required String content,
    required String timeStr,
    required String type,
  }) {
    Color themeColor = Colors.black;
    Color bgColor = Colors.grey[100]!;
    IconData iconData = Icons.notifications_rounded;

    // 對接 ServicePage 的三個溫度狀態等級
    if (type == 'danger') {
      themeColor = Colors.red;
      bgColor = Colors.red[50]!;
      iconData = Icons.gpp_bad_rounded; // 與 ServicePage 相同的危險盾牌
    } else if (type == 'warn') {
      themeColor = Colors.amber[800]!;
      bgColor = Colors.amber[50]!;
      iconData = Icons.gpp_maybe_rounded; // 與 ServicePage 相同的警告盾牌
    } else {
      themeColor = Colors.black;
      bgColor = Colors.grey[100]!;
      iconData = Icons.schedule_rounded; // 排程或一般通知
    }

    return Dismissible(
      key: Key(notificationId),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 28),
      ),
      onDismissed: (direction) {
        FirebaseDatabase.instance.ref('users/$_uid/notifications/$notificationId').remove();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: bgColor,
              radius: 22,
              child: Icon(iconData, color: themeColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: themeColor,
                        ),
                      ),
                      Text(
                        _formatTime(timeStr),
                        style: const TextStyle(fontSize: 12, color: Colors.black26),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    content,
                    style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String isoTimestamp) {
    if (isoTimestamp.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTimestamp).toLocal();
      return "${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return isoTimestamp;
    }
  }
}
