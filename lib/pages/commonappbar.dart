import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 💡 引入以取得目前登入使用者
import 'ai.dart'; // 確保此處引入的是你新版定義了 Zone, Device, AppNotification 的 ai.dart

class CommonAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showBackButton;
  final List<Widget>? actions;
  final bool showAiAssistant; // ✨ 是否顯示 AI 助理按鈕（預設開啟）

  const CommonAppBar({
    super.key, 
    this.showBackButton = true,
    this.actions,
    this.showAiAssistant = true, // 預設每個頁面都顯示 AI 助理
  });

  // 💡 修改名稱為 _openAiAssistantSheet 避開與 showAiAssistant 變數衝突
  void _openAiAssistantSheet(BuildContext context, String userId) {
    final databaseRef = FirebaseDatabase.instance.ref();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        // 🔄 使用 StreamBuilder 實時監聽該使用者的 Firebase 資料
        return StreamBuilder<DatabaseEvent>(
          stream: databaseRef.child('users/$userId').onValue,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.black),
              );
            }

            // 💡 防呆：如果沒資料或出錯，傳入空陣列，避免 AiChatSheet 建構子少傳參數報錯
            if (snapshot.hasError || !snapshot.hasData || snapshot.data?.snapshot.value == null) {
              return const AiChatSheet(zones: [], notifications: []);
            }

            // 📦 開始解析從 Firebase 拿到的原始 Map 資料
            final rawData = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);

            // 1. 解析 Zones (對應你新版的 Zone 與 Device 巢狀結構)
            List<Zone> loadedZones = [];
            if (rawData['zones'] != null) {
              final zonesMap = Map<dynamic, dynamic>.from(rawData['zones']);
              zonesMap.forEach((key, value) {
                if (value is Map) {
                  final zoneData = Map<dynamic, dynamic>.from(value);
                  loadedZones.add(Zone.fromMap(key.toString(), zoneData));
                }
              });
            }

            // 2. 解析 Notifications (對應你新版的 AppNotification 結構)
            List<AppNotification> loadedNotifications = [];
            if (rawData['notifications'] != null) {
              final notificationsMap = Map<dynamic, dynamic>.from(rawData['notifications']);
              notificationsMap.forEach((key, value) {
                if (value is Map) {
                  final notifData = Map<dynamic, dynamic>.from(value);
                  loadedNotifications.add(AppNotification.fromMap(key.toString(), notifData));
                }
              });
            }

            // 🚀 將實時資料，直接丟給你的 AI 助理！
            return AiChatSheet(
              zones: loadedZones,
              notifications: loadedNotifications,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 組合自訂的 actions 與 AI 助理按鈕
    List<Widget> finalActions = [];
    if (actions != null) {
      finalActions.addAll(actions!);
    }
    
    if (showAiAssistant) {
      finalActions.add(
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(1.5, 1.5),
                  )
                ],
              ),
              child: const Icon(
                Icons.smart_toy_rounded, // 🤖 超可愛的機器人圖示
                color: Colors.black,
                size: 20,
              ),
            ),
            onPressed: () {
              // 💡 點擊時，獲取目前登入使用者的 UID 並開啟實時監聽助理
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                _openAiAssistantSheet(context, uid);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('尚未登入，無法取得 AI 助理資料')),
                );
              }
            },
          ),
        ),
      );
    }

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true, 
      leading: showBackButton 
        ? IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 20),
            onPressed: () => Navigator.maybePop(context),
          )
        : null,
      title: Row(
        mainAxisSize: MainAxisSize.min, 
        children: [
          Image.asset(
            'assets/logo.png', 
            height: 32,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.timer_outlined, color: Colors.black, size: 32), // 避免路徑沒配好報錯
          ),
          const SizedBox(width: 10),
          const Text(
            'Smart Timer',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
      actions: finalActions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
