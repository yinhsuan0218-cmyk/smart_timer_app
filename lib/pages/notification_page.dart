import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'service_page.dart';

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
        content: const Text("確定要清空所有的操作通知與溫度警報紀錄嗎？"),
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

  // 點擊高溫嚴重警告通知時彈出的 Danger 對話框
  void _showDangerDialog({
    required String notificationId,
    required String zoneName,
    required String content,
    required String temperature,
  }) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF8B0000), // 暗紅色背景
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
            SizedBox(width: 8),
            Text('危險！溫度過高', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '目前區域【$zoneName】環境溫度已達 $temperature°C（已超過安全上限 80.0°C）。\n\n⚠️ 系統已強制切斷該區域內所有高負載裝置電源！\n\n系統紀錄：$content',
          style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (notificationId.isNotEmpty && _uid != null) {
                await FirebaseDatabase.instance
                    .ref('users/$_uid/notifications/$notificationId')
                    .update({'status': 'read'});
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('收到警告並確認安全性', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                    final String type = item['type'] ?? 'info'; 
                    final String status = item['status'] ?? 'unread';
                    final String zoneName = item['zone_name'] ?? '特定區域'; 
                    final String temperature = item['temperature']?.toString() ?? '未知';

                    return _buildNotificationItem(
                      notificationId: notificationId,
                      title: title,
                      content: content,
                      timeStr: timeStr,
                      type: type,
                      status: status,
                      zoneName: zoneName,
                      temperature: temperature,
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

  Widget _buildNotificationItem({
    required String notificationId,
    required String title,
    required String content,
    required String timeStr,
    required String type,
    required String status,
    required String zoneName,
    required String temperature,
  }) {
    Color themeColor;
    Color bgColor;
    IconData iconData;

    if (type == 'danger') {
      themeColor = const Color(0xFFD32F2F); // 警報紅
      bgColor = status == 'read' ? const Color(0xFFFFF8F8) : const Color(0xFFFFEBEE); 
      iconData = Icons.gpp_bad_rounded;
    } else if (type == 'warn') {
      // 🔌 耗電異常：顯示黃色/橘色
      themeColor = const Color(0xFFE65100); // 警告橘深黃
      bgColor = status == 'read' ? const Color(0xFFFFFDE7) : const Color(0xFFFFF3E0); 
      iconData = Icons.offline_bolt_rounded; // 更換為更貼切的電力圖示
    } else if (type == 'success') {
      // 🌱 耗電/環境恢復正常：顯示安全綠
      themeColor = const Color(0xFF2E7D32); // 安全綠
      bgColor = status == 'read' ? const Color(0xFFF4F9F4) : const Color(0xFFE8F5E9); 
      iconData = Icons.gpp_good_rounded;   
    } else {
      themeColor = const Color(0xFF1976D2); // 一般操作藍
      bgColor = status == 'read' ? const Color(0xFFF5F9FD) : const Color(0xFFE3F2FD);
      iconData = Icons.toggle_on_rounded; 
    }

    return Dismissible(
      key: Key(notificationId),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 28),
      ),
      onDismissed: (direction) {
        if (_uid != null) {
          FirebaseDatabase.instance.ref('users/$_uid/notifications/$notificationId').remove();
        }
      },
      child: InkWell(
        onTap: () {
          if (type == 'danger') {
            _showDangerDialog(
              notificationId: notificationId,
              zoneName: zoneName,
              content: content,
              temperature: temperature,
            );
          } else {
            // 一般電器通知、耗電警告(warn)與恢復(success)點擊，直接轉為已讀
            if (_uid != null && status == 'unread') {
              FirebaseDatabase.instance
                  .ref('users/$_uid/notifications/$notificationId')
                  .update({'status': 'read'});
            }
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6.0),
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: themeColor.withOpacity(status == 'read' ? 0.1 : 0.3), 
              width: status == 'read' ? 0.8 : 1.2,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: Colors.white,
                radius: 20,
                child: Icon(iconData, color: themeColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: themeColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (status == 'unread' && (type == 'danger' || type == 'warn'))
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                                  child: const Text("未確認", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          _formatTime(timeStr),
                          style: TextStyle(fontSize: 11, color: themeColor.withOpacity(0.6)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      content,
                      style: TextStyle(
                        fontSize: 13, 
                        color: status == 'read' ? Colors.black45 : Colors.black87, 
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
