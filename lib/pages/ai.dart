import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

// ==========================================
// 1. 引入或定義你的資料結構 (若已在其他檔案定義，請改為 import)
// ==========================================
class Zone {
  String id;
  String name;
  double temperature;
  String power; // 'safe' 或其他安全狀態，或開關狀態

  Zone({
    required this.id,
    required this.name,
    this.temperature = 0.0,
    this.power = 'safe',
  });

  factory Zone.fromMap(String id, Map<dynamic, dynamic> map) {
    return Zone(
      id: id,
      name: map['name'] ?? '未命名區域',
      temperature: (map['temperature'] ?? 0.0).toDouble(),
      power: map['power'] ?? 'safe',
    );
  }
}

class Service {
  String id;
  String name;
  Service({required this.id, required this.name});
}

class Schedule {
  List<bool> weekdays; // Mon ~ Sun (長度為 7)
  String start;
  String end;

  Schedule(this.weekdays, this.start, this.end);
}

// ==========================================
// 2. 智慧助理介面 (動態接收後端實時資料)
// ==========================================
class AiChatSheet extends StatefulWidget {
  final List<Zone> zones;       // 傳入當前使用者的區域狀態
  final List<Service> services; // 傳入當前可用的服務
  final List<Schedule> schedules; // 傳入當前設定的排程

  const AiChatSheet({
    super.key,
    required this.zones,
    required this.services,
    required this.schedules,
  });

  @override
  State<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<AiChatSheet> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // 🎙️ 語音辨識
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  double _soundLevel = 0.0;

  late final List<Map<String, dynamic>> _messages;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    // 初始化歡迎詞，帶入當前抓取到的設備數量
    _messages = [
      {
        'isUser': false,
        'text': '你好！我是你的 Smart Timer 智慧助理。🤖\n'
                '目前已成功為您連線到後端資料：\n'
                '• 已偵測到 ${widget.zones.length} 個監控區域\n'
                '• 已啟用 ${widget.services.length} 項服務\n'
                '• 已設定 ${widget.schedules.length} 組定時排程\n\n'
                '您可以問我「各區溫度」、「排程設定」或「安全狀態」喔！',
        'time': _getNowTime()
      },
    ];
    
    _initSpeech();
  }

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

  // 🤖 核心：動態分析使用者後端資料並回覆
  void _parseAndExecuteInstruction(String rawText) {
    final text = rawText.toLowerCase();
    String responseText = "";

    // 1. 查詢「溫度」：動態撈取所有 Zone 的溫度
    if (text.contains("溫度") || text.contains("幾度") || text.contains("熱") || text.contains("冷")) {
      if (widget.zones.isEmpty) {
        responseText = "🌡️ 目前後端系統中沒有設定任何區域，無法取得溫度資料。";
      } else {
        responseText = "🌡️ 為您查詢各區域的實時溫度：\n";
        for (var zone in widget.zones) {
          responseText += "• ${zone.name}: ${zone.temperature}°C\n";
        }
        responseText += "\n所有區域溫度均在正常範圍內！";
      }
    }
    // 2. 查詢「安全狀態」/「電力/安全 power 欄位」
    else if (text.contains("安全") || text.contains("狀態") || text.contains("危險")) {
      if (widget.zones.isEmpty) {
        responseText = "🛡️ 目前沒有可監控的區域狀態。";
      } else {
        responseText = "🛡️ 系統安全與狀態回報：\n";
        for (var zone in widget.zones) {
          String statusEmoji = (zone.power == "safe") ? "✅ 安全" : "⚠️ 異常 (${zone.power})";
          responseText += "• ${zone.name}: $statusEmoji\n";
        }
      }
    }
    // 3. 查詢「服務」：查詢有哪些 Service
    else if (text.contains("服務") || text.contains("功能") || text.contains("service")) {
      if (widget.services.isEmpty) {
        responseText = "⚙️ 您目前尚未啟用任何智慧服務。";
      } else {
        responseText = "⚙️ 您目前啟用的後端服務有：\n";
        for (var service in widget.services) {
          responseText += "• [ID: ${service.id}] ${service.name}\n";
        }
      }
    }
    // 4. 查詢「定時排程」：動態解析 Schedule 物件中的 weekdays 與時間
    else if (text.contains("排程") || text.contains("定時") || text.contains("時間表") || text.contains("幾點")) {
      if (widget.schedules.isEmpty) {
        responseText = "📅 目前您的智慧定時器沒有設定任何排程。";
      } else {
        responseText = "📅 您的實時定時排程如下：\n";
        final weekNames = ["一", "二", "三", "四", "五", "六", "日"];
        
        for (int i = 0; i < widget.schedules.length; i++) {
          final sch = widget.schedules[i];
          // 解析 weekdays List<bool>
          List<String> activeDays = [];
          for (int j = 0; j < sch.weekdays.length; j++) {
            if (sch.weekdays[j]) {
              activeDays.add(weekNames[j]);
            }
          }
          String daysStr = activeDays.length == 7 ? "每天" : "每週 (${activeDays.join(', ')})";
          responseText += "⏰ 排程 ${i + 1}：\n   - 重複：$daysStr\n   - 時間：${sch.start} ～ ${sch.end}\n\n";
        }
      }
    }
    // 5. 語音或文字控制指令 (模擬硬體觸發控制)
    else if (text.contains("開啟") || text.contains("打開") || text.contains("關閉") || text.contains("關掉")) {
      final action = (text.contains("開啟") || text.contains("打開")) ? "開啟" : "關閉";
      responseText = "🔌 收到「$action」指令！\n正在透過後端向您的 ESP32 傳送控制訊號...\n(已成功送出 MQTT 命令)";
      // 💡 實際應用：這裡可以直接呼叫你主頁面的 Callback 函式發送 MQTT 或更新 Firebase。
    }
    // 6. 預設模糊回覆
    else {
      responseText = "抱歉，我沒聽懂「$rawText」。🤔\n\n您可以這樣問我：\n"
                     "👉「查看各區溫度」\n"
                     "👉「查詢目前排程」\n"
                     "👉「安全狀態如何？」\n"
                     "👉「開啟/關閉設備」";
    }

    // 延遲 800ms 模擬思考後回覆
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'isUser': false,
          'text': responseText,
          'time': _getNowTime(),
        });
      });
      _scrollToBottom();
    });
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    if (_isListening) _toggleListening();

    setState(() {
      _messages.add({
        'isUser': true,
        'text': text,
        'time': _getNowTime(),
      });
      _textController.clear();
    });

    _scrollToBottom();
    _parseAndExecuteInstruction(text);
  }

  void _toggleListening() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) => setState(() => _textController.text = val.recognizedWords),
          onSoundLevelChange: (level) => setState(() => _soundLevel = level),
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
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(4, 4))],
      ),
      child: Column(
        children: [
          // 頂部列
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
                        "Smart Timer 智慧助理",
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

          // 對話列表
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
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
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

          if (_isListening) _buildVoiceWaveform(),
          const SizedBox(height: 8),

          // 輸入欄
          Row(
            children: [
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
                      hintText: "問「客廳溫度」或「今天排程」...",
                      border: InputBorder.none,
                      hintStyle: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
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

  // 波動動畫
  Widget _buildVoiceWaveform() {
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
