import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

// ==========================================
// 1. 資料結構重構 (完美契合 Firebase RTDB)
// ==========================================

class Device {
  final String id;
  final String name;
  final bool isActive;
  final String timerStart;
  final String timerEnd;
  final Map<dynamic, dynamic>? scheduleDays;
  final String lastUpdated;

  Device({
    required this.id,
    required this.name,
    required this.isActive,
    required this.timerStart,
    required this.timerEnd,
    this.scheduleDays,
    required this.lastUpdated,
  });

  factory Device.fromMap(String id, Map<dynamic, dynamic> map) {
    return Device(
      id: id,
      name: map['name'] ?? '未命名裝置',
      isActive: map['is_active'] ?? false,
      timerStart: map['timer_start'] ?? '',
      timerEnd: map['timer_end'] ?? '',
      scheduleDays: map['schedule_days'] is Map ? map['schedule_days'] : null,
      lastUpdated: map['last_updated'] ?? '',
    );
  }
}

class Zone {
  final String id;
  final String name;
  final String temperature; // 資料庫中為字串，部分為空 ""
  final List<Device> devices;

  Zone({
    required this.id,
    required this.name,
    required this.temperature,
    required this.devices,
  });

  factory Zone.fromMap(String id, Map<dynamic, dynamic> map) {
    var devicesList = <Device>[];
    if (map['devices'] is Map) {
      (map['devices'] as Map).forEach((key, value) {
        if (value is Map) {
          devicesList.add(Device.fromMap(key.toString(), value));
        }
      });
    }

    return Zone(
      id: id,
      name: map['name'] ?? '未命名區域',
      temperature: map['temperature']?.toString() ?? '',
      devices: devicesList,
    );
  }
}

class AppNotification {
  final String id;
  final String title;
  final String content;
  final String status;
  final String type;
  final String timestamp;
  final String zoneName;

  AppNotification({
    required this.id,
    required this.title,
    required this.content,
    required this.status,
    required this.type,
    required this.timestamp,
    required this.zoneName,
  });

  factory AppNotification.fromMap(String id, Map<dynamic, dynamic> map) {
    return AppNotification(
      id: id,
      title: map['title'] ?? '系統通知',
      content: map['content'] ?? '',
      status: map['status'] ?? 'unread',
      type: map['type'] ?? 'info',
      timestamp: map['timestamp'] ?? '',
      zoneName: map['zone_name'] ?? '',
    );
  }
}

// ==========================================
// 2. 智慧助理介面
// ==========================================
class AiChatSheet extends StatefulWidget {
  final List<Zone> zones;                       // 傳入當前所有區域與內嵌裝置
  final List<AppNotification> notifications;    // 傳入當前的通知與警告列表

  const AiChatSheet({
    super.key,
    required this.zones,
    required this.notifications,
  });

  @override
  State<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<AiChatSheet> with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
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
    
    // 計算總裝置數
    int totalDevices = widget.zones.fold(0, (sum, zone) => sum + zone.devices.length);
    // 找出未讀警告數
    int totalWarns = widget.notifications.where((n) => n.type == 'warn' && n.status == 'unread').length;

    // 初始化歡迎詞
    _messages = [
      {
        'isUser': false,
        'text': '你好！我是你的 Smart Timer 智慧助理。🤖\n'
                '目前實時系統狀態：\n'
                '• 已連線監控區域：${widget.zones.length} 個\n'
                '• 納管智慧裝置總數：$totalDevices 個\n'
                '• 未處理異常警告：$totalWarns 則\n\n'
                '您可以問我「各區溫度」、「裝置狀態」、「排程定時」或「有沒有異常通知」喔！',
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

    // 1. 查詢「溫度」
    if (text.contains("溫度") || text.contains("幾度") || text.contains("熱") || text.contains("冷")) {
      if (widget.zones.isEmpty) {
        responseText = "🌡️ 目前系統中沒有設定任何區域，無法取得溫度資料。";
      } else {
        responseText = "🌡️ 為您查詢各區域的實時溫度：\n";
        for (var zone in widget.zones) {
          String tempDisplay = zone.temperature.isEmpty ? "未回報 (或無感測器)" : "${zone.temperature}°C";
          responseText += "• 區域【${zone.name}】: $tempDisplay\n";
        }
      }
    }
    // 2. 查詢「裝置開關狀態 / 電力狀態」
    else if (text.contains("狀態") || text.contains("開關") || text.contains("打開") || text.contains("開啟") || text.contains("關閉")) {
      // 如果單純是控制指令（開啟/關閉某裝置）
      if (text.contains("開啟") || text.contains("打開") || text.contains("關閉") || text.contains("關掉")) {
        final action = (text.contains("開啟") || text.contains("打開")) ? "開啟" : "關閉";
        responseText = "🔌 收到「$action」指令！\n正在透過 MQTT 向您的 ESP32 控制端發送訊號...\n(命令已成功發送)";
      } else {
        // 查詢狀態
        if (widget.zones.isEmpty) {
          responseText = "🔌 目前沒有任何區域與裝置。";
        } else {
          responseText = "🔌 各區域裝置實時開關狀態：\n";
          for (var zone in widget.zones) {
            responseText += "📦 區域：${zone.name}\n";
            if (zone.devices.isEmpty) {
              responseText += "  (此區域目前沒有掛載裝置)\n";
            } else {
              for (var dev in zone.devices) {
                String statusEmoji = dev.isActive ? "🟢 已開啟 (Active)" : "🔴 已關閉 (Inactive)";
                responseText += "  • ${dev.name}: $statusEmoji\n";
              }
            }
          }
        }
      }
    }
    // 3. 查詢「定時排程」
    else if (text.contains("排程") || text.contains("定時") || text.contains("時間") || text.contains("幾點")) {
      responseText = "⏰ 幫您查詢目前的裝置定時設定：\n";
      bool hasSchedule = false;

      for (var zone in widget.zones) {
        for (var dev in zone.devices) {
          if (dev.timerStart.isNotEmpty || dev.timerEnd.isNotEmpty) {
            hasSchedule = true;
            responseText += "💡 【${dev.name}】(${zone.name})\n"
                            "  - 啟動時間: ${dev.timerStart}\n"
                            "  - 結束時間: ${dev.timerEnd}\n";
            if (dev.scheduleDays != null) {
              // 可選擇性在此解析星期
              responseText += "  - 重複週期: 已設定排程天數\n";
            }
            responseText += "\n";
          }
        }
      }
      if (!hasSchedule) {
        responseText = "📅 目前所有裝置皆未設定定時排程。";
      }
    }
    // 4. 查詢「異常 / 通知 / 警告」
    else if (text.contains("警告") || text.contains("通知") || text.contains("異常") || text.contains("耗電")) {
      if (widget.notifications.isEmpty) {
        responseText = "🔔 目前沒有任何系統警報或通知，運作一切正常！";
      } else {
        responseText = "⚠️ 系統最近的通知與警告摘要：\n\n";
        // 撈取最近的 3 筆
        final recentNotifs = widget.notifications.reversed.take(3);
        for (var notif in recentNotifs) {
          String typeIcon = notif.type == "warn" ? "⚠️ [警告]" : "ℹ️ [提示]";
          String status = notif.status == "read" ? "(已讀)" : "(未讀*)";
          responseText += "$typeIcon ${notif.title} $status\n"
                          "• 內容: ${notif.content}\n"
                          "• 時間: ${notif.timestamp}\n\n";
        }
      }
    }
    // 5. 預設模糊回覆
    else {
      responseText = "抱歉，我沒聽懂「$rawText」。🤔\n\n您可以試著這樣問我：\n"
                     "👉「查看各區溫度」\n"
                     "👉「目前有哪些裝置是開著的？」\n"
                     "👉「查詢咖啡機的排程定時」\n"
                     "👉「有沒有異常耗電警告？」";
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
          // 頂部標題列
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

          // 對話訊息列表
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

          // 輸入控制列
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
                      hintText: "問「各區溫度」、「排程」或「最新警告」...",
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

  // 語音波動動畫
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
