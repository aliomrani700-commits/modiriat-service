from pathlib import Path

src = Path('lib/app_v12.dart')
x = src.read_text()

# Add SMS master switch state to settings.
x = x.replace(
"    this.autoBackup = true,\n  });",
"    this.autoBackup = true,\n    this.smsEnabled = true,\n    this.smsPausedAt = '',\n  });"
)
x = x.replace(
"  bool autoBackup;",
"  bool autoBackup, smsEnabled;\n  String smsPausedAt;"
)
x = x.replace(
"        'autoBackup': autoBackup,\n      };",
"        'autoBackup': autoBackup,\n        'smsEnabled': smsEnabled,\n        'smsPausedAt': smsPausedAt,\n      };"
)
x = x.replace(
"        autoBackup: j['autoBackup'] != false,\n      );",
"        autoBackup: j['autoBackup'] != false,\n        smsEnabled: j['smsEnabled'] != false,\n        smsPausedAt: j['smsPausedAt']?.toString() ?? '',\n      );"
)

# Do not schedule anything while master SMS switch is off.
x = x.replace(
"  Future<void> _schedule(Customer c) async {\n    if (c.phone.trim().isEmpty || c.nextServiceDate.trim().isEmpty) return;",
"  Future<void> _schedule(Customer c) async {\n    if (!settings.smsEnabled) return;\n    if (c.phone.trim().isEmpty || c.nextServiceDate.trim().isEmpty) return;"
)

anchor = "  Future<void> _scheduleAll() async { for (final c in customers) { await _schedule(c); } }\n"
extra = r'''

  Future<void> _cancelAllSms() async {
    for (final c in customers) {
      try {
        await _channel.invokeMethod('cancelSms', {'id': c.id.hashCode & 0x7fffffff});
      } catch (_) {}
    }
  }

  Future<void> _setSmsEnabled(bool enabled) async {
    if (enabled == settings.smsEnabled) return;
    if (!enabled) {
      settings.smsEnabled = false;
      settings.smsPausedAt = DateTime.now().toIso8601String();
      await _cancelAllSms();
      await _saveCore(dailyBackup: false);
      return;
    }

    final pausedAt = DateTime.tryParse(settings.smsPausedAt);
    settings.smsEnabled = true;
    settings.smsPausedAt = '';
    await _saveCore(dailyBackup: false);

    if (!(await Permission.sms.status).isGranted) return;
    final now = DateTime.now();
    for (final c in customers) {
      if (c.phone.trim().isEmpty || c.nextServiceDate.trim().isEmpty) continue;
      final when = parseServiceDate(c.nextServiceDate, settings);
      if (when == null) continue;
      if (pausedAt != null && !when.isBefore(pausedAt) && !when.isAfter(now)) {
        try {
          await _channel.invokeMethod('sendSmsNow', {
            'phone': c.phone.trim(),
            'message': smsFor(c),
          });
        } catch (_) {}
      } else if (when.isAfter(now)) {
        await _schedule(c);
      }
    }
  }
'''
if '_setSmsEnabled(bool enabled)' not in x:
    x = x.replace(anchor, anchor + extra)

x = x.replace(
"SettingsScreen(settings:settings,templates:templates,onSave:()async{await _saveCore();await _scheduleAll();})",
"SettingsScreen(settings:settings,templates:templates,onSave:()async{await _saveCore();await _scheduleAll();},onSmsToggle:_setSmsEnabled)"
)

x = x.replace(
"const SettingsScreen({super.key,required this.settings,required this.templates,required this.onSave});final AppSettings settings;final List<SmsTemplate> templates;final Future<void> Function() onSave;",
"const SettingsScreen({super.key,required this.settings,required this.templates,required this.onSave,required this.onSmsToggle});final AppSettings settings;final List<SmsTemplate> templates;final Future<void> Function() onSave;final Future<void> Function(bool) onSmsToggle;"
)

x = x.replace(
"late TextEditingController seller,p1,p2,card,shaba;late int hour,minute;late bool autoBackup;",
"late TextEditingController seller,p1,p2,card,shaba;late int hour,minute;late bool autoBackup,smsEnabled;"
)
x = x.replace(
"autoBackup=widget.settings.autoBackup;}",
"autoBackup=widget.settings.autoBackup;smsEnabled=widget.settings.smsEnabled;}"
)

x = x.replace(
"Future<void> _save()async{widget.settings..sellerName=seller.text.trim()..sellerPhone1=p1.text.trim()..sellerPhone2=p2.text.trim()..cardNumber=card.text.trim()..shaba=shaba.text.trim()..smsHour=hour..smsMinute=minute..autoBackup=autoBackup;await widget.onSave();if(mounted)Navigator.pop(context);}",
"Future<void> _save()async{widget.settings..sellerName=seller.text.trim()..sellerPhone1=p1.text.trim()..sellerPhone2=p2.text.trim()..cardNumber=card.text.trim()..shaba=shaba.text.trim()..smsHour=hour..smsMinute=minute..autoBackup=autoBackup;await widget.onSmsToggle(smsEnabled);await widget.onSave();if(mounted)Navigator.pop(context);}"
)

marker = "const Text('پیامک یادآوری',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),"
switch_ui = "SwitchListTile(value:smsEnabled,onChanged:(v)=>setState(()=>smsEnabled=v),title:const Text('ارسال خودکار پیامک'),subtitle:Text(smsEnabled?'فعال است؛ پیام‌ها طبق زمان‌بندی ارسال می‌شوند':'متوقف است؛ پیام‌های این بازه بعد از فعال‌سازی ارسال می‌شوند')),const SizedBox(height:8),"
if switch_ui not in x:
    x = x.replace(marker, marker + switch_ui)

src.write_text(x)
