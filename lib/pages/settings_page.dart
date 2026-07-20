import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // 1. 使用者狀態 (預設: 在家)
  String _userStatus = 'home'; // 'home', 'away', 'sleep'

  // 2. 自訂雙色主題 (預設: 白底 黑字/框/圖)
  Color _backgroundColor = Colors.white;
  Color _primaryColor = Colors.black;

  String? _uid;

  // 預設可選擇的常用質感顏色選項
  final List<Color> _presetColors = [
    Colors.black,
    Colors.white,
    const Color(0xFF1E88E5), // 寶藍
    const Color(0xFF2E7D32), // 森林綠
    const Color(0xFFD32F2F), // 質感紅
    const Color(0xFFE65100), // 鮮橘
    const Color(0xFF6A1B9A), // 深紫
    const Color(0xFF37474F), // 鐵灰
    const Color(0xFFF4F5F7), // 淺灰白
    const Color(0xFFFFF8E1), // 暖米黃
  ];

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _loadSettings();
  }

  // 讀取設定 (Firebase 狀態 + SharedPreferences 主題色)
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _backgroundColor = Color(prefs.getInt('bg_color') ?? Colors.white.value);
      _primaryColor = Color(prefs.getInt('primary_color') ?? Colors.black.value);
    });

    if (_uid != null) {
      final snapshot = await FirebaseDatabase.instance.ref('users/$_uid/status').get();
      if (snapshot.exists && snapshot.value != null) {
        setState(() {
          _userStatus = snapshot.value.toString();
        });
      }
    }
  }

  // 更新使用者狀態並寫入 Firebase
  Future<void> _updateUserStatus(String status) async {
    setState(() {
      _userStatus = status;
    });

    if (_uid != null) {
      await FirebaseDatabase.instance.ref('users/$_uid').update({
        'status': status,
        'status_updated_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已切換模式為：${_getStatusLabel(status)}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  // 儲存顏色至 SharedPreferences
  Future<void> _saveColor(String key, Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, color.value);
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'away':
        return '出門狀態 🚪';
      case 'sleep':
        return '睡眠狀態 🌙';
      case 'home':
      default:
        return '在家狀態 🏠';
    }
  }

  // 原生色彩選單對話框
  void _showNativeColorPicker(BuildContext context, bool isBackground) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: _backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: _primaryColor, width: 1.5),
          ),
          title: Text(
            isBackground ? '選擇背景顏色' : '選擇主要顏色',
            style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
          ),
          // 👇 這裡改成 SizedBox + GridView
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true, // 讓高度根據內容自適應
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5, // 每行顯示 5 個顏色
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: _presetColors.length,
              itemBuilder: (context, index) {
                final color = _presetColors[index];
                final bool isSelected = isBackground
                    ? _backgroundColor.value == color.value
                    : _primaryColor.value == color.value;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isBackground) {
                        _backgroundColor = color;
                        _saveColor('bg_color', color);
                      } else {
                        _primaryColor = color;
                        _saveColor('primary_color', color);
                      }
                    });
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? _primaryColor : Colors.grey.shade400,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            size: 20,
                            color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text(
          "系統設定",
          style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
        ),
        backgroundColor: _backgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: _primaryColor),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ----------------------------------------------------
          // 區塊 1：使用者狀態切換 (在家 / 出門 / 睡眠)
          // ----------------------------------------------------
          Text(
            "目前模式狀態",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _primaryColor,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatusCard('home', '在家', Icons.home_rounded),
              const SizedBox(width: 10),
              _buildStatusCard('away', '出門', Icons.directions_run_rounded),
              const SizedBox(width: 10),
              _buildStatusCard('sleep', '睡眠', Icons.bedtime_rounded),
            ],
          ),

          const SizedBox(height: 32),
          Divider(color: _primaryColor.withOpacity(0.2)),
          const SizedBox(height: 16),

          // ----------------------------------------------------
          // 區塊 2：App 雙色主題自訂
          // ----------------------------------------------------
          Text(
            "自訂 App 風格配色",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _primaryColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "可選擇背景與主要元素（文字、外框線、圖示）的專屬色彩",
            style: TextStyle(fontSize: 12, color: _primaryColor.withOpacity(0.6)),
          ),
          const SizedBox(height: 16),

          // 設定背景顏色
          _buildColorTile(
            title: "背景顏色",
            subtitle: "改變頁面底色",
            color: _backgroundColor,
            onTap: () => _showNativeColorPicker(context, true),
          ),

          const SizedBox(height: 12),

          // 設定主要元素顏色
          _buildColorTile(
            title: "主要元素顏色",
            subtitle: "影響文字、外框與圖案顏色",
            color: _primaryColor,
            onTap: () => _showNativeColorPicker(context, false),
          ),

          const SizedBox(height: 32),

          // ----------------------------------------------------
          // 區塊 3：即時預覽效果卡片
          // ----------------------------------------------------
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _backgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _primaryColor, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_rounded, color: _primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      "配色預覽效果",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _primaryColor,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "這是一段測試文字，框線與圖示都會套用您所選擇的主色彩！",
                  style: TextStyle(color: _primaryColor.withOpacity(0.8), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 狀態選擇按鈕卡片組件
  Widget _buildStatusCard(String statusKey, String label, IconData icon) {
    final bool isSelected = _userStatus == statusKey;

    return Expanded(
      child: GestureDetector(
        onTap: () => _updateUserStatus(statusKey),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? _primaryColor : _backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _primaryColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? _backgroundColor : _primaryColor,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? _backgroundColor : _primaryColor,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 顏色選擇列組件
  Widget _buildColorTile({
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryColor.withOpacity(0.3), width: 1),
      ),
      child: ListTile(
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, color: _primaryColor),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: _primaryColor.withOpacity(0.6), fontSize: 12),
        ),
        trailing: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: _primaryColor, width: 2),
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
