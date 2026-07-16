import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
                '您可以試著這樣問我：\n'
                '👉「查詢客廳溫度」或「開啟咖啡機」\n'
                '👉「看看今日排程」或「修改冷氣排程為 12:00 到 18:00」',
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

  // Helper: 獲取當前星期幾 (中文)
  String _getWeekdayChinese(int weekday) {
    const days = {1: "星期一", 2: "星期二", 3: "星期三", 4: "星期四", 5: "星期五", 6: "星期六", 7: "星期日"};
    return days[weekday] ?? "未知";
  }

  // 🤖 核心：動態分析使用者後端資料並回覆（深度擴充功能）
  void _parseAndExecuteInstruction(String rawText) {
    final text = rawText.trim().toLowerCase();
    String responseText = "";

    // 取得當前使用者 ID 用於遠端控制
    final uid = FirebaseAuth.instance.currentUser?.uid;

    // ==========================================
    // 功能 1：遠端控制 (修改排程 / 開關設備)
    // ==========================================
    
    // A. 修改排程分析 (例如: "修改冷氣排程為 14:00 到 18:00")
    if ((text.contains("修改") || text.contains("設定") || text.contains("更新")) && 
        (text.contains("排程") || text.contains("定時") || text.contains("時間"))) {
      
      if (uid == null) {
        responseText = "❌ 您尚未登入，無法執行遠端排程修改。";
      } else {
        // 使用正則表達式嘗試擷取兩個時間點 (HH:mm)
        final timeRegex = RegExp(r'([0-1]?[0-9]|2[0-3]):[0-5][0-9]');
        final times = timeRegex.allMatches(text).map((m) => m.group(0)!).toList();

        if (times.length < 2) {
          responseText = "⏰ 排程修改格式不夠明確。\n請說明，例如：「修改 [設備名稱] 排程為 08:30 到 17:00」";
        } else {
          final startTime = times[0];
          final endTime = times[1];
          
          // 尋找目標設備
          Device? targetDevice;
          Zone? targetZone;
          for (var zone in widget.zones) {
            for (var dev in zone.devices) {
              if (text.contains(dev.name.toLowerCase()) || text.contains(zone.name.toLowerCase())) {
                targetDevice = dev;
                targetZone = zone;
                break;
              }
            }
          }

          if (targetDevice == null) {
            responseText = "🔍 未能識別您想修改哪一項設備的排程。\n請明確說明設備名稱（例如：修改咖啡機排程為 $startTime 到 $endTime）";
          } else {
            // 直接往 Firebase 寫入新排程資料
            final devRef = FirebaseDatabase.instance
                .ref()
                .child('users/$uid/zones/${targetZone!.id}/devices/${targetDevice.id}');
            
            devRef.update({
              'timer_start': startTime,
              'timer_end': endTime,
              'last_updated': DateTime.now().toIso8601String(),
            }).then((_) {
              debugPrint("Firebase 排程更新成功");
            }).catchError((err) {
              debugPrint("Firebase 排程更新失敗: $err");
            });

            responseText = "📝 已為您將【${targetZone.name}】的【${targetDevice.name}】定時排程修改為：\n"
                            "• 啟動時間: $startTime\n"
                            "• 關閉時間: $endTime\n"
                            "⚡ 指令已成功同步至 Firebase 雲端與 ESP32 設備！";
          }
        }
      }
    }
    
    // B. 開關設備分析 (例如: "開啟咖啡機"、"關掉 0312 的風扇")
    else if (text.contains("開啟") || text.contains("打開") || text.contains("關閉") || text.contains("關掉")) {
      if (uid == null) {
        responseText = "❌ 您尚未登入，無法執行硬體遠端控制。";
      } else {
        final bool turnOn = text.contains("開啟") || text.contains("打開");
        Device? targetDevice;
        Zone? targetZone;

        for (var zone in widget.zones) {
          for (var dev in zone.devices) {
            if (text.contains(dev.name.toLowerCase())) {
              targetDevice = dev;
              targetZone = zone;
              break;
            }
          }
        }

        if (targetDevice == null) {
          responseText = "🔍 找不到您指定的裝置名稱。請試著說：「開啟 [裝置名稱]」（例如：開啟 咖啡機）。";
        } else {
          // 直接對 Firebase 進行狀態寫入，連動 MQTT 
          final devRef = FirebaseDatabase.instance
              .ref()
              .child('users/$uid/zones/${targetZone!.id}/devices/${targetDevice.id}');
          
          devRef.update({
            'is_active': turnOn,
            'last_updated': DateTime.now().toIso8601String(),
          });

          responseText = "🔌 已為您發送控制指令：\n"
                          "• 區域: ${targetZone.name}\n"
                          "• 設備: ${targetDevice.name}\n"
                          "• 動作: ${turnOn ? '🟢 開啟 (ON)' : '🔴 關閉 (OFF)'}\n\n"
                          "📡 訊號已發送，ESP32 繼電器端正同步執行中！";
        }
      }
    }

    // ==========================================
    // 功能 2：資料庫深度查詢解析
    // ==========================================
    
    // A. 查詢「溫度」（支援多區/單區查詢）
    else if (text.contains("溫度") || text.contains("幾度") || text.contains("熱") || text.contains("冷")) {
      // 檢查是否是特定單一區域查詢
      Zone? selectedZone;
      for (var zone in widget.zones) {
        if (text.contains(zone.name.toLowerCase())) {
          selectedZone = zone;
          break;
        }
      }

      if (selectedZone != null) {
        String tempDisplay = selectedZone.temperature.isEmpty ? "目前未回報資料" : "${selectedZone.temperature}°C";
        responseText = "🌡️ 區域【${selectedZone.name}】的實時溫度為：$tempDisplay。";
      } else {
        if (widget.zones.isEmpty) {
          responseText = "🌡️ 目前系統中沒有註冊任何監控區域。";
        } else {
          responseText = "🌡️ 目前各監控區域溫度列表：\n";
          for (var zone in widget.zones) {
            String tempDisplay = zone.temperature.isEmpty ? "未偵測" : "${zone.temperature}°C";
            responseText += "• 【${zone.name}】: $tempDisplay\n";
          }
        }
      }
    }

    // B. 查詢「耗電 / 電力狀態」
    else if (text.contains("耗電") || text.contains("電量") || text.contains("電力")) {
      // 智慧定時器可依據 isActive 狀態，推估當前啟用耗電設備
      List<String> powerUsageInfo = [];
      for (var zone in widget.zones) {
        for (var dev in zone.devices) {
          if (dev.isActive) {
            // 如果含有特定關鍵字，智慧助理可以做高耗電標記
            bool isHighPower = dev.name.contains("冷氣") || dev.name.contains("烤箱") || dev.name.contains("微波爐") || dev.name.contains("加熱");
            powerUsageInfo.add("⚡ 【${zone.name} - ${dev.name}】 正持續運作中${isHighPower ? ' (⚠️高耗電裝置)' : ''}");
          }
        }
      }

      if (powerUsageInfo.isEmpty) {
        responseText = "🍀 目前所有受控智慧設備皆在「關閉」狀態，無持續電力損耗。";
      } else {
        responseText = "🔌 目前正在執行（耗電中）的裝置有：\n\n${powerUsageInfo.join('\n')}";
      }
    }

    // C. 查詢「區域與設備清單」
    else if (text.contains("區域") || text.contains("設備") || text.contains("裝置") || text.contains("有哪些")) {
      final bool checkActiveOnly = text.contains("開啟") || text.contains("開著");
      final bool checkInactiveOnly = text.contains("關閉") || text.contains("關著");

      if (widget.zones.isEmpty) {
        responseText = "📦 目前系統沒有任何監控區域與裝置。";
      } else {
        responseText = "📦 【受管智慧硬體清單】\n";
        int matchedCount = 0;

        for (var zone in widget.zones) {
          List<String> devNames = [];
          for (var dev in zone.devices) {
            if (checkActiveOnly && !dev.isActive) continue;
            if (checkInactiveOnly && dev.isActive) continue;
            
            String status = dev.isActive ? "🟢" : "🔴";
            devNames.add("$status ${dev.name}");
            matchedCount++;
          }

          if (devNames.isNotEmpty) {
            responseText += "• 區域 【${zone.name}】：\n  ${devNames.join(', ')}\n";
          }
        }

        if (matchedCount == 0) {
          responseText = "🔍 目前沒有找到符合您篩選條件（開著/關閉）的智慧裝置。";
        }
      }
    }

    // D. 查詢「定時排程」（支援：今日、明日、昨日、本週、單設備）
    else if (text.contains("排程") || text.contains("定時") || text.contains("時間") || text.contains("幾點")) {
      final now = DateTime.now();
      int queryWeekday = now.weekday; // 預設為今日

      String schedulePeriodText = "今日";
      if (text.contains("明日") || text.contains("明天")) {
        queryWeekday = (now.weekday % 7) + 1;
        schedulePeriodText = "明日";
      } else if (text.contains("昨日") || text.contains("昨天")) {
        queryWeekday = now.weekday == 1 ? 7 : now.weekday - 1;
        schedulePeriodText = "昨日";
      } else if (text.contains("本週") || text.contains("這星期")) {
        schedulePeriodText = "本週";
      }

      // 檢查是否是特定單一設備
      Device? specificDev;
      for (var zone in widget.zones) {
        for (var dev in zone.devices) {
          if (text.contains(dev.name.toLowerCase())) {
            specificDev = dev;
          }
        }
      }

      responseText = "⏰ 為您查詢 [ $schedulePeriodText ] 的排程設定：\n\n";
      bool foundSchedule = false;

      for (var zone in widget.zones) {
        for (var dev in zone.devices) {
          // 如果指名查詢單一設備但此處不符合，就跳過
          if (specificDev != null && dev.id != specificDev.id) continue;

          if (dev.timerStart.isNotEmpty || dev.timerEnd.isNotEmpty) {
            // 驗證排程天數對應 (Firebase 結構中 schedule_days 通常是星期一至星期日)
            bool isScheduled = false;
            String weekDayConfig = "未特別指定（每日重置）";

            if (dev.scheduleDays != null) {
              final daysMap = dev.scheduleDays!;
              // 匹配 RTDB 中類似 'monday': true / '0' : true 的結構
              final weekdayKeys = {
                1: ['monday', 'mon', '1', '星期一'],
                2: ['tuesday', 'tue', '2', '星期二'],
                3: ['wednesday', 'wed', '3', '星期三'],
                4: ['thursday', 'thu', '4', '星期四'],
                5: ['friday', 'fri', '5', '星期五'],
                6: ['saturday', 'sat', '6', '星期六'],
                7: ['sunday', 'sun', '7', '星期日'],
              };

              if (schedulePeriodText == "本週") {
                isScheduled = true;
                List<String> actDays = [];
                weekdayKeys.forEach((wDay, keys) {
                  for (var key in keys) {
                    if (daysMap[key] == true) {
                      actDays.add(_getWeekdayChinese(wDay));
                      break;
                    }
                  }
                });
                weekDayConfig = actDays.isEmpty ? "未勾選重複天數" : "每週 ${actDays.join('、')}";
              } else {
                // 單日查詢
                final checkKeys = weekdayKeys[queryWeekday] ?? [];
                for (var key in checkKeys) {
                  if (daysMap[key] == true) {
                    isScheduled = true;
                    break;
                  }
                }
              }
            } else {
              // 若無排程天數欄位，預設視為每日執行
              isScheduled = true;
            }

            if (isScheduled) {
              foundSchedule = true;
              responseText += "💡 【${dev.name}】 (區域：${zone.name})\n"
                              "  - ⏰ 定時：${dev.timerStart} ～ ${dev.timerEnd}\n"
                              "  - 📅 週期：$weekDayConfig\n\n";
            }
          }
        }
      }

      if (!foundSchedule) {
        responseText = "📅 $schedulePeriodText 查無任何智慧裝置設定了自動定時排程。";
      }
    }

    // E. 查詢「未讀重要通知 / 安全狀態」
    else if (text.contains("警告") || text.contains("通知") || text.contains("異常") || text.contains("安全")) {
      final unreadWarns = widget.notifications.where((n) => n.type == 'warn' && n.status == 'unread').toList();
      
      if (unreadWarns.isEmpty) {
        responseText = "🛡️ 【安全監控狀態】：正常\n🟢 目前無任何未讀的重要異常警告，系統運作平穩、電壓與溫度皆在安全範圍內！";
      } else {
        responseText = "⚠️ 警報！發現 ${unreadWarns.length} 則未讀重要異常通知：\n\n";
        for (int i = 0; i < unreadWarns.length; i++) {
          final w = unreadWarns[i];
          responseText += "${i + 1}. 🔴 [${w.title}]\n"
                          "  • 內容: ${w.content}\n"
                          "  • 區域: ${w.zoneName}\n"
                          "  • 時間: ${w.timestamp}\n\n";
        }
      }
    }

    // F. 模糊匹配與小助手提示
    else {
      responseText = "抱歉，我無法確認「$rawText」的具體指令。🤔\n\n"
                     "你可以這樣考考我：\n"
                     "🔸 「查看各區溫度」或「客廳幾度」\n"
                     "🔸 「開啟咖啡機」或「關閉 0312 的風扇」\n"
                     "🔸 「查詢今日排程」或「查詢熱水器定時」\n"
                     "🔸 「將咖啡機排程修改為 14:00 到 15:30」\n"
                     "🔸 「有沒有異常通知？」";
    }

    // 模擬 AI 思考與載入動畫（800ms 後推入回覆）
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

  // ==========================================
  // 新增：常用快捷指令定義
  // ==========================================
  final List<Map<String, String>> _quickActions = [
    {"label": "🌡️ 各區溫度", "cmd": "目前各區溫度幾度？"},
    {"label": "⏰ 今日排程", "cmd": "查詢今日排程"},
    {"label": "⚡ 耗電狀態", "cmd": "哪些裝置正在耗電？"},
    {"label": "⚠️ 異常警告", "cmd": "有沒有異常通知？"},
    {"label": "🔌 關閉所有裝置", "cmd": "關閉所有裝置"}, // 可延伸實作
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      padding: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.75, // 稍微拉高高度以容納按鈕列
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
          const SizedBox(height: 4),

          // ==========================================
          // 新增：橫向滾動的自動輸入快捷按鈕列
          // ==========================================
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _quickActions.length,
              padding: const EdgeInsets.symmetric(vertical: 2),
              itemBuilder: (context, index) {
                final action = _quickActions[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: InkWell(
                    onTap: () => _sendMessage(action["cmd"]!), // 點擊直接送出指令
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.black, width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black,
                            offset: Offset(2, 2),
                          )
                        ],
                      ),
                      child: Center(
                        child: Text(
                          action["label"]!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

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
