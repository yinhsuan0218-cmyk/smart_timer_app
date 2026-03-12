import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'nav_page.dart';
import 'commonappbar.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> signIn(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const NavPage()),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('登入失敗: $e'),
            behavior: SnackBarBehavior.floating, // 現代化的浮動式提示
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonAppBar(showBackButton: false),
      backgroundColor: Colors.white, // 純白底色
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 標題與簡介
              const Text(
                'Welcome To Smart Timer',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '登入使用app',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 60),

              // 現代化登入按鈕
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () => signIn(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.black12, width: 1.5), // 細黑線條感
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30), // 高弧度圓角
                    ),
                    foregroundColor: Colors.black,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 模擬 Google Icon 的空間 (如有 asset 可換成 Image)
                      const Icon(Icons.login_rounded, size: 20),
                      const SizedBox(width: 12),
                      const Text(
                        '使用 Google 帳號登入',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              // 底部裝飾線條或文字
              // 底部裝飾線條或文字
              TextButton(
                onPressed: () {
                  // 彈出宗旨小視窗
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      title: const Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: Colors.black),
                          SizedBox(width: 10),
                          Text('軟體宗旨', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      content: const Column(
                        mainAxisSize: MainAxisSize.min, // 讓視窗長度隨內容縮放
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Smart Timer 致力於簡化您的家居自動化體驗。',
                            style: TextStyle(fontWeight: FontWeight.bold, height: 1.5),
                          ),
                          SizedBox(height: 12),
                          Text(
                            '我們透過直覺的排程介面與穩定的 MQTT 技術，讓您隨時隨地精準掌控設備運作，達成節能環保與便利生活的美好願景。',
                            style: TextStyle(color: Colors.black87, height: 1.5),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            '我知道了',
                            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text(
                  '需要協助？',
                  style: TextStyle(color: Colors.black45, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}