import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:firebase_database/firebase_database.dart'; 
import 'package:firebase_auth/firebase_auth.dart';     
import 'home_page.dart';
import 'zone_page.dart';
import 'user_page.dart';
import 'commonappbar.dart';
import 'notification_page.dart'; 

class NavPage extends StatefulWidget {
  const NavPage({super.key});

  @override
  State<NavPage> createState() => _NavPageState();
}

class _NavPageState extends State<NavPage> {
  int _selectedIndex = 1;
  int _tutorialStep = 0;
  
  // ★ 區分為紅、藍兩種類型的未讀計數
  int _redCount = 0;   // 溫度異常警報數 (danger, warn)
  int _blueCount = 0;  // 電器操作與排程數 (info)
  
  String? uid;
  DatabaseReference? _notificationRef;

  @override
  void initState() {
    super.initState();
    _checkFirstTime();
    _setupNotificationListener(); 
  }

  // ★ 核心邏輯：即時監聽並分類計算紅、藍通知數量
  void _setupNotificationListener() {
    uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _notificationRef = FirebaseDatabase.instance.ref('users/$uid/notifications');
      
      _notificationRef!.onValue.listen((event) {
        if (event.snapshot.value != null) {
          // 如果使用者目前就停在通知頁面(Index 2)，直接清空計數，不顯示紅藍點
          if (_selectedIndex == 2) {
            setState(() {
              _redCount = 0;
              _blueCount = 0;
            });
            return;
          }

          final data = event.snapshot.value as Map<dynamic, dynamic>;
          int tempRed = 0;
          int tempBlue = 0;

          // 遍歷所有通知，依據 type 歸類
          data.forEach((key, value) {
            if (value != null) {
              final item = Map<String, dynamic>.from(value as Map);
              final String type = item['type'] ?? 'info';

              if (type == 'danger' || type == 'warn') {
                tempRed++;
              } else {
                tempBlue++;
              }
            }
          });

          setState(() {
            _redCount = tempRed;
            _blueCount = tempBlue;
          });
        } else {
          setState(() {
            _redCount = 0;
            _blueCount = 0;
          });
        }
      });
    }
  }

  // 修改後的檢查邏輯
  Future<void> _checkFirstTime() async {
    // 取得當前登入使用者的 uid
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return; // 如果沒登入就先不處理

    final prefs = await SharedPreferences.getInstance();
    
    // ★ 關鍵：將 Key 綁定 UID（例如：hasSeenTutorial_user123）
    // 這樣才能確保「這個帳號」在這台手機上是第一次登入
    String tutorialKey = 'hasSeenTutorial_$currentUid';
    bool hasSeenTutorial = prefs.getBool(tutorialKey) ?? false;

    if (!hasSeenTutorial) {
      // 確保畫面已經渲染完成後，再延時彈出對話框
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _showStep1(prefs, tutorialKey);
        }
      });
    }
  }

  // 傳入 prefs 與 key，在使用者點擊確認、真正看完教學時才寫入本地紀錄
  void _showStep1(SharedPreferences prefs, String tutorialKey) {
    _showTutorialDialog(
      title: "歡迎使用！",
      content: "為了安全，請先前往「User」分頁填寫您的wifi帳號密碼以及電話號碼。",
      buttonText: "前往 User 頁面",
      onConfirm: () async {
        setState(() {
          _selectedIndex = 3; // 切換到 User 頁面
          _tutorialStep = 2;
        }); 
        
        // ★ 使用者點了按鈕、確定看完後，再正式將狀態改為 true
        await prefs.setBool(tutorialKey, true);
      },
    );
  }

  void _showTutorialDialog({
    required String title,
    required String content,
    required String buttonText,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: Text(buttonText, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  final List<Widget> _pages = [
    const ZonePage(),         
    const HomePage(),         
    const NotificationPage(), 
    const UserPage(),         
  ];

  // 💡 自訂雙色高質感外掛 Badge 組件
  Widget _buildDualBadgeIcon(IconData iconData) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(iconData),
        Positioned(
          top: -6,
          right: -12,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔴 紅色警報點
              if (_redCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD32F2F),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_redCount',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              // 🔵 藍色操作點
              if (_blueCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1976D2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_blueCount',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonAppBar(showBackButton: false), 
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.black12, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
              // ★ 當點擊進入通知頁面時，將所有計數歸零，提示點消失
              if (index == 2) {
                _redCount = 0;
                _blueCount = 0;
              }
            });
          },
          backgroundColor: Colors.white,
          selectedItemColor: Colors.black, 
          unselectedItemColor: Colors.black26, 
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          showSelectedLabels: true,
          showUnselectedLabels: false,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_outlined),
              activeIcon: Icon(Icons.grid_view_rounded),
              label: 'Zone',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            
            // 💡 替換為支援雙色未讀標籤的 Notice 按鈕
            BottomNavigationBarItem(
              icon: _buildDualBadgeIcon(Icons.notifications_outlined),
              activeIcon: _buildDualBadgeIcon(Icons.notifications_rounded),
              label: 'Notice',
            ),

            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'User',
            ),
          ],
        ),
      ),
    );
  }
}
