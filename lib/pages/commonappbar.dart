import 'package:flutter/material.dart';

class CommonAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showBackButton;
  final List<Widget>? actions;

  const CommonAppBar({
    super.key, 
    this.showBackButton = true,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true, // 讓 Logo 和文字居中
      leading: showBackButton 
        ? IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 20),
            onPressed: () => Navigator.maybePop(context),
          )
        : null,
      title: Row(
        mainAxisSize: MainAxisSize.min, // 縮小 Row 以便在中心對齊
        children: [
          // 你的 Logo 圖片
          Image.asset(
            'assets/logo.png', // 確保你的 pubspec.yaml 有設定路徑
            height: 32,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 10),
          // App 名字
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
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}