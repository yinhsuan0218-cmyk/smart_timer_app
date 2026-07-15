import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt; // 🎙️ 引入語音套件

class AiChatSheet extends StatefulWidget {
  const AiChatSheet({super.key});

  @override
  State<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<AiChatSheet> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // 🎙️ 語音辨識實例
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  double _soundLevel = 0.0; // 偵測到的音量大小，可用來讓波形隨說話音量跳動！

  final List<Map<String, dynamic>> _messages = [
    {
      'isUser': false,
      'text': '你好！我是你的 Smart Timer 智慧助理。你可以問我關於定時排程、設備狀態或節能建議喔！',
      'time': '12:00'
    },
  ];

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _initSpeech();
  }

  // 初始化語音辨識
  void _initSpeech() async {
    try {
      await _speech.initialize(
        onError: (val) => debugPrint('語音辨識錯誤: $val'),
        onStatus: (val) => debugPrint('語音狀態: $val'),
      );
    } catch (e) {
      debugPrint('語音辨識初始化失敗: $e');
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    _speech.stop();
    super.dispose();
  }

  // 觸發或停止語音聆聽
  void _toggleListening() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              _textController.text = val.recognizedWords;
            });
          },
          onSoundLevelChange: (level) { // ✨ 修改為 onSoundLevelChange 即可！
            setState(() {
              _soundLevel = level;
            });
          },
          localeId: 'zh_TW',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法啟用語音辨識服務，請確認權限是否開啟')),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  // 發送訊息
  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    
    // 如果正在錄音，發送時自動停止錄音
    if (_isListening) {
      _toggleListening();
    }

    setState(() {
      _messages.add({
        'isUser': true,
        'text': text,
        'time': _getNowTime(),
      });
      _textController.clear();
    });

    _scrollToBottom();

    // 模擬 AI 回覆（未來可在此處直接 http.post 串接 Gemini/OpenAI API）
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'isUser': false,
          'text': '收到您的指令！我正在為您分析「$text」...',
          'time': _getNowTime(),
        });
      });
      _scrollToBottom();
    });
  }

  String _getNowTime() {
    final now = DateTime.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      padding: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black,
            offset: Offset(4, 4),
          )
        ],
      ),
      child: Column(
        children: [
          // 頂部 Handle 與 標題
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.psychology_alt_rounded, color: Colors.black, size: 28),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "AI 智慧助理",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                      Text(
                        _isListening ? "正在聆聽您的指令..." : "在線解答您的指令",
                        style: TextStyle(
                          fontSize: 11, 
                          color: _isListening ? Colors.red : Colors.grey[600],
                          fontWeight: _isListening ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.black),
              )
            ],
          ),
          const Divider(height: 16, color: Colors.black12),

          // 💬 訊息對話列表
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final bool isUser = msg['isUser'];

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.black : Colors.grey[100],
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
                        bottomRight: isUser ? Radius.zero : const Radius.circular(16),
                      ),
                      border: Border.all(color: Colors.black, width: 1.2),
                    ),
                    child: Text(
                      msg['text'],
                      style: TextStyle(
                        color: isUser ? Colors.white : Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 🎙️ 語音辨識即時音量跳動波形
          if (_isListening) _buildVoiceWaveform(),

          const SizedBox(height: 8),

          // ⌨️ 下方輸入欄位與控制項
          Row(
            children: [
              // 🎙️ 語音按鈕
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: _isListening 
                              ? Colors.red.withOpacity(0.4 * _animationController.value) 
                              : Colors.transparent,
                          blurRadius: 8,
                          spreadRadius: 4,
                        )
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: _isListening ? Colors.red : Colors.black,
                      ),
                      onPressed: _toggleListening,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              
              // 📝 文字輸入框
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: TextField(
                    controller: _textController,
                    onSubmitted: _sendMessage,
                    decoration: const InputDecoration(
                      hintText: "打字或點左側語音輸入...",
                      border: InputBorder.none,
                      hintStyle: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // ✉️ 發送按鈕
              Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                  onPressed: () => _sendMessage(_textController.text),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 🌊 音量動態跳動波形
  Widget _buildVoiceWaveform() {
    // 限制 soundLevel 轉換範圍，防止跳動幅度過大
    double normalizedVolume = (_soundLevel + 2).clamp(0.0, 12.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[300]!, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(7, (index) {
          // 透過音量與 index 的數學正弦組合，計算出超滑順、具備層次感的音量起伏動態
          double waveFactor = (index == 3) 
              ? normalizedVolume 
              : (index == 2 || index == 4) 
                  ? normalizedVolume * 0.7 
                  : normalizedVolume * 0.4;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: 4,
            height: 10 + waveFactor * 2.5,
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}
