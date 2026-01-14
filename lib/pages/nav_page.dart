import 'package:flutter/material.dart';
import 'home_page.dart';
import 'zone_page.dart';
import 'user_page.dart';
import 'commonappbar.dart';

class NavPage extends StatefulWidget {
  const NavPage({super.key});

  @override
  State<NavPage> createState() => _NavPageState();
}

class _NavPageState extends State<NavPage> {
  int _selectedIndex = 1; 
  int _tutorialStep = 0; // 0: 未開始, 1: 提醒去 UserPage, 2: 提醒去 ZonePage...

  @override
  void initState() {
    super.initState();
    // 延遲 1 秒後顯示歡迎畫面與 Step 1
    Future.delayed(const Duration(seconds: 1), () => _showStep1());
  }

  // Step 1: 歡迎與指引前往 UserPage
  void _showStep1() {
    _showTutorialDialog(
      title: "歡迎使用！",
      content: "為了安全，請先前往「User」分頁填寫您的電話號碼。",
      buttonText: "前往 User 頁面",
      onConfirm: () {
        setState(() => _selectedIndex = 2); // 跳轉到 UserPage
        _tutorialStep = 2; // 下一個邏輯在 UserPage 完成時觸發
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

  // 定義導覽列要切換的頁面清單
  final List<Widget> _pages = [
    const ZonePage(), // Index 0
    const HomePage(), // Index 1
    const UserPage(), // Index 2
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonAppBar(showBackButton: false), // 登入頁通常不需要返回
      // 使用 IndexedStack 可以讓切換頁面時保持滾動位置，且不會重新載入
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
            });
          },
          backgroundColor: Colors.white,
          selectedItemColor: Colors.black, // 選中為純黑
          unselectedItemColor: Colors.black26, // 未選中為淺灰
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          showSelectedLabels: true,
          showUnselectedLabels: false,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_outlined),
              activeIcon: Icon(Icons.grid_view_rounded),
              label: 'Zone',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
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