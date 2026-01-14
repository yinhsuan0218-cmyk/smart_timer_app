import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'nav_page.dart';
import 'commonappbar.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> signIn(BuildContext context) async {
    try {
      // Mobile 端的 Google 登入流程
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

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
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
      body: SafeArea( // 確保在手機瀏海屏區域內
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 1. 頂部圖示或裝飾 (使用簡單的圓弧圖形)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black12, width: 1),
                  ),
                  child: const Icon(
                    Icons.account_circle_outlined,
                    size: 80,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 40),

                // 2. 歡迎文字 (置中)
                const Text(
                  'Welcome To Smart Timer',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '登入使用app',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 60),

                // 3. 現代化黑線條圓弧按鈕
                SizedBox(
                  width: double.infinity,
                  height: 58, // 稍微加高，手機點擊感更好
                  child: OutlinedButton(
                    onPressed: () => signIn(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.black, width: 1.2), // 黑線條
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30), // 全圓角弧線
                      ),
                      foregroundColor: Colors.black,
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.login_rounded, size: 22),
                        SizedBox(width: 12),
                        Text(
                          '使用 Google 帳號登入',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // 4. 底部隱私提示 (User-friendly 的細節)
                Text(
                  '需要協助？',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}