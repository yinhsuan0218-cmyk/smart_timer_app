import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'login_page.dart';

class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  final user = FirebaseAuth.instance.currentUser;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false; // 新增：讀取狀態控制

  @override
  void initState() {
    super.initState();
    // 1. 先填入 Auth 的基本資料作為預設值
    _emailController.text = user?.email ?? '';
    
    // 2. 觸發異步讀取資料庫
    _loadUserData();
  }

  // 從 Realtime Database 讀取電話與自定義資料
  Future<void> _loadUserData() async {
    if (user == null) return;
    
    try {
      final DatabaseReference userRef = FirebaseDatabase.instance.ref('users/${user!.uid}');
      final snapshot = await userRef.get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        
        // 使用 setState 更新 UI
        setState(() {
          if (data.containsKey('phone')) {
            _phoneController.text = data['phone'].toString();
          }
          if (data.containsKey('email')) {
            _emailController.text = data['email'].toString();
          }
        });
      }
    } catch (e) {
      debugPrint("讀取資料庫失敗: $e");
    }
  }

  Future<void> _saveAndNext() async {
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請填寫電話號碼以利緊急通知')),
      );
      return;
    }

    setState(() => _isLoading = true); // 開始儲存，進入讀取狀態

    if (user != null) {
      try {
        final DatabaseReference userRef = FirebaseDatabase.instance.ref('users/${user!.uid}');
        
        await userRef.update({
          'name': user?.displayName ?? '未設定',
          'email': email,
          'phone': phone,
          'last_updated': DateTime.now().toIso8601String(),
        });

        if (!mounted) return;
        _showSuccessDialog(); // 獨立出彈窗方法
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('儲存失敗：$e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _showSuccessDialog() {
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text("我知道了", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('登出確認', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('您確定要登出 Smart Timer 嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()), 
                  (route) => false,
                );
              }
            },
            child: const Text('確定登出', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
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
            const SizedBox(height: 60),
            const Text(
              'User Info Setup',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 30),
            
            // 頭像部分
            Center(
              child: CircleAvatar(
                radius: 55,
                backgroundColor: Colors.grey[200],
                foregroundImage: (user?.photoURL != null) ? NetworkImage(user!.photoURL!) : null,
                child: const Icon(Icons.person, size: 55, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 40),

            _buildInfoField(label: '名稱', content: user?.displayName ?? '未設定', icon: Icons.face_rounded),
            const SizedBox(height: 20),
            _buildEditField(label: '綁定的 Google 帳號', controller: _emailController, icon: Icons.alternate_email_rounded),
            const SizedBox(height: 20),
            _buildEditField(label: '電話號碼', controller: _phoneController, icon: Icons.phone_android_rounded, keyboardType: TextInputType.phone),
            const SizedBox(height: 40),

            // 更新按鈕 (增加 Loading 判斷)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveAndNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('更新並繼續', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),

            // 登出按鈕
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton.icon(
                onPressed: () => _showSignOutDialog(context), 
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

  // --- UI 小組件 ---
  Widget _buildInfoField({required String label, required String content, required IconData icon}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.black54)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.black12)),
          child: Row(children: [Icon(icon, size: 20, color: Colors.black38), const SizedBox(width: 12), Text(content, style: const TextStyle(color: Colors.black45))]),
        ),
      ],
    );
  }

  Widget _buildEditField({required String label, required TextEditingController controller, required IconData icon, TextInputType keyboardType = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.black54)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.black, size: 20),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.black12)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.black, width: 1.2)),
          ),
        ),
      ],
    );
  }
}