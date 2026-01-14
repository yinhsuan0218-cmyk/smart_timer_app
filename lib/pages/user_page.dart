import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'commonappbar.dart';

class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  final user = FirebaseAuth.instance.currentUser;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _emailController.text = user?.email ?? '';
    _phoneController.text = user?.phoneNumber ?? '';
  }

  // 教學邏輯：儲存並指引
  void _saveAndNext() {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請填寫電話號碼以利緊急通知')),
      );
      return;
    }

    // 這裡實作 Firebase 儲存邏輯 (例如 user.updatePhoneNumber)
    // ...

    // 彈出教學指引
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text("完成第一步！", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("資訊已更新。現在請點擊下方的「Zone」分頁，開始建立您的智慧空間。"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // 提示：這裡可以透過回傳或通知讓 NavPage 切換到 Index 0
            },
            child: const Text("我知道了", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const Text(
                'User Info Setup',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  letterSpacing: 1.2,
                ),
              ),
            const SizedBox(height: 30),
            
            // 0. 頭像
            Center(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.2),
                ),
                child: CircleAvatar(
                  radius: 55,
                  backgroundColor: Colors.grey[100],
                  backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                  child: user?.photoURL == null ? const Icon(Icons.person, size: 55, color: Colors.black26) : null,
                ),
              ),
            ),
            const SizedBox(height: 40),

            _buildInfoField(
              label: '名稱',
              content: user?.displayName ?? '未設定',
              icon: Icons.face_rounded,
            ),
            
            const SizedBox(height: 20),

            _buildEditField(
              label: '綁定的 Google 帳號',
              controller: _emailController,
              icon: Icons.alternate_email_rounded,
            ),

            const SizedBox(height: 20),

            _buildEditField(
              label: '電話號碼',
              controller: _phoneController,
              icon: Icons.phone_android_rounded,
              keyboardType: TextInputType.phone,
            ),

            const SizedBox(height: 40),

            // 主儲存按鈕 (教學指引明顯位置)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _saveAndNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  elevation: 0,
                ),
                child: const Text('更新並繼續', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),

            const SizedBox(height: 20),

            // 登出按鈕
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('登出帳號', style: TextStyle(fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent, width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoField({required String label, required String content, required IconData icon}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Colors.black38),
              const SizedBox(width: 12),
              Text(content, style: const TextStyle(fontSize: 16, color: Colors.black45)),
              const Spacer(),
              const Icon(Icons.lock_outline_rounded, size: 16, color: Colors.black12),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditField({required String label, required TextEditingController controller, required IconData icon, TextInputType keyboardType = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          cursorColor: Colors.black,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.black, size: 20),
            hintText: '請輸入$label',
            hintStyle: const TextStyle(color: Colors.black12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: Colors.black12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: Colors.black, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }
}