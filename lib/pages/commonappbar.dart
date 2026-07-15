import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 💡 引入以取得目前登入使用者
import 'ai.dart';

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

            if (snapshot.hasError || !snapshot.hasData || snapshot.data?.snapshot.value == null) {
              // 💡 修正：如果沒資料或出錯，傳入空陣列，避免 AiChatSheet 建構子少傳參數報錯
              return const AiChatSheet(zones: [], services: [], schedules: []);
            }

            // 📦 開始解析從 Firebase 拿到的原始 Map 資料
            final rawData = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);

            // 1. 解析 Zones (對應你的 Zone class)
            List<Zone> loadedZones = [];
            if (rawData['zones'] != null) {
              final zonesMap = Map<dynamic, dynamic>.from(rawData['zones']);
              zonesMap.forEach((key, value) {
                final zoneData = Map<dynamic, dynamic>.from(value);
                
                // 💡 關鍵安全防護：在這裡就做好溫度的防呆解析
                double parsedTemp = 0.0;
                final rawTemp = zoneData['temperature'];
                if (rawTemp != null) {
                  if (rawTemp is num) {
                    parsedTemp = rawTemp.toDouble();
                  } else if (rawTemp is String) {
                    parsedTemp = double.tryParse(rawTemp) ?? 0.0;
                  }
                }

                loadedZones.add(Zone(
                  id: key.toString(),
                  name: zoneData['name'] ?? '未命名區域',
                  temperature: parsedTemp, // ✨ 帶入安全解析後的溫度
                  power: zoneData['power'] ?? 'safe',
                ));
              });
            }

            // 2. 解析 Services (對應你的 Service class)
            List<Service> loadedServices = [];
            if (rawData['services'] != null) {
              final servicesMap = Map<dynamic, dynamic>.from(rawData['services']);
              servicesMap.forEach((key, value) {
                final serviceData = Map<dynamic, dynamic>.from(value);
                loadedServices.add(Service(
                  id: key.toString(),
                  name: serviceData['name'] ?? '未命名服務',
                ));
              });
            }

            // 3. 解析 Schedules (對應你的 Schedule class)
            List<Schedule> loadedSchedules = [];
            if (rawData['schedules'] != null) {
              final schedulesList = List<dynamic>.from(rawData['schedules']);
              for (var item in schedulesList) {
                if (item != null) {
                  final schMap = Map<dynamic, dynamic>.from(item);
                  // 將 Firebase 的 [true, true...] 轉成 List<bool>
                  final List<bool> weekdays = List<bool>.from(schMap['weekdays'] ?? List.filled(7, false));
                  loadedSchedules.add(Schedule(
                    weekdays,
                    schMap['start'] ?? '00:00',
                    schMap['end'] ?? '00:00',
                  ));
                }
              }
            }

            // 🚀 將實時資料，直接丟給你的 AI 助理！
            return AiChatSheet(
              zones: loadedZones,
              services: loadedServices,
              schedules: loadedSchedules,
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
