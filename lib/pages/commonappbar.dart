import 'package:flutter/material.dart';
import 'ai.dart';
class CommonAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showBackButton;
  final List<Widget>? actions;
  final bool showAiAssistant; // ✨ 新增：是否顯示 AI 助理按鈕（預設開啟）

  const CommonAppBar({
    super.key, 
    this.showBackButton = true,
    this.actions,
    this.showAiAssistant = true, // 預設每個頁面都顯示 AI 助理
  });

  // 🤖 彈出 AI 智慧對話視窗
  void _showAiChatSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 允許高度隨鍵盤彈出自動調整
      backgroundColor: Colors.transparent, 
      builder: (context) {
        return const AiChatSheet();
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
            onPressed: () => _showAiChatSheet(context),
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
