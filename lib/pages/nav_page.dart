import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:firebase_database/firebase_database.dart'; // ★ 新增：引入 Firebase 監聽數量
import 'package:firebase_auth/firebase_auth.dart';     // ★ 新增：取得 UID
import 'home_page.dart';
import 'zone_page.dart';
import 'user_page.dart';
import 'commonappbar.dart';
import 'notification_page.dart'; // ★ 確保引入你的通知頁面

class NavPage extends StatefulWidget {
  const NavPage({super.key});

  @override
  State<NavPage> createState() => _NavPageState();
}

class _NavPageState extends State<NavPage> {
  int _selectedIndex = 1;
  int _tutorialStep = 0;
  
  // ★ 修改：從寫死改成動態。0 代表沒有訊息，紅點會自動隱藏
  int _messageCount = 0; 
  String? uid;
  DatabaseReference? _notificationRef;

  @override
  void initState() {
    super.initState();
    _checkFirstTime();
    _setupNotificationListener(); // ★ 新增：啟動 Firebase 通知監聽器
  }

  // ★ 新增核心邏輯：即時監聽 Firebase 有幾條通知，並反映在紅點上
  void _setupNotificationListener() {
    uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _notificationRef = FirebaseDatabase.instance.ref('users/$uid/notifications');
      
      // 監聽 Firebase 數據變化
      _notificationRef!.onValue.listen((event) {
        if (event.snapshot.value != null) {
          final data = event.snapshot.value as Map<dynamic, dynamic>;
          
          // 如果當前已經切換在通知頁面(Index 2)，我們就不顯示未讀紅點
          if (_selectedIndex == 2) {
            setState(() => _messageCount = 0);
          } else {
            setState(() => _messageCount = data.length); // 有幾筆資料，紅點就顯示幾點
          }
        } else {
          setState(() => _messageCount = 0);
        }
      });
    }
  }

  // ★★★ 核心邏輯：檢查是否為第一次進入 ★★★
  Future<void> _checkFirstTime() async {
    final prefs = await SharedPreferences.getInstance();
    bool hasSeenTutorial = prefs.getBool('hasSeenTutorial') ?? false;

    if (!hasSeenTutorial) {
      Future.delayed(const Duration(seconds: 1), () => _showStep1());
      await prefs.setBool('hasSeenTutorial', true);
    }
  }

  // Step 1: 歡迎與指引前往 UserPage
  void _showStep1() {
    _showTutorialDialog(
      title: "歡迎使用！",
      content: "為了安全，請先前往「User」分頁填寫您的wifi帳號密碼以及電話號碼。",
      buttonText: "前往 User 頁面",
      onConfirm: () {
        setState(() => _selectedIndex = 3); 
        _tutorialStep = 2;
      },
    );
  }

  // 通用的教學彈窗風格 (黑白圓角)
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

  // ★ 關鍵修改：將清單裡原本的暫時文字，正式替換成實體的 NotificationPage()
  final List<Widget> _pages = [
    const ZonePage(),         // Index 0
    const HomePage(),         // Index 1
    const NotificationPage(), // ★ Index 2: 正式對接你的通知頁面
    const UserPage(),         // Index 3
  ];

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
              // ★ 當點擊進入通知頁面（Index 2）時，將未讀訊息歸零，紅點直接消失
              if (index == 2) {
                _messageCount = 0;
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
            
            // 訊息通知 Icon
            BottomNavigationBarItem(
              icon: Badge(
                label: Text('$_messageCount'), 
                isLabelVisible: _messageCount > 0, // 數量大於 0 才顯示紅點
                backgroundColor: Colors.red, 
                textColor: Colors.white, 
                child: const Icon(Icons.notifications_outlined),
              ),
              activeIcon: Badge(
                label: Text('$_messageCount'),
                isLabelVisible: _messageCount > 0,
                backgroundColor: Colors.red,
                child: const Icon(Icons.notifications_rounded),
              ),
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
