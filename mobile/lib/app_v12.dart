import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamsi_date/shamsi_date.dart';

const _storageKey = 'modiriat_service_customers_v1';
const _templatesKey = 'modiriat_service_sms_templates_v1';
const _settingsKey = 'modiriat_service_settings_v2';
const _dailyBackupKey = 'modiriat_service_last_daily_backup';
const _tasksKey = 'modiriat_service_daily_tasks_v1';
const _channel = MethodChannel('modiriat_service/sms');

void runModiriatService() => runApp(const ModiriatServiceApp());

class ModiriatServiceApp extends StatelessWidget {
  const ModiriatServiceApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مدیریت سرویس',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E), brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF4F7F8),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey.shade200)),
        ),
      ),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink()),
      home: const HomeScreen(),
    );
  }
}

class AppSettings {
  AppSettings({
    this.sellerName = 'کارنوپلاس',
    this.sellerPhone1 = '09123492589',
    this.sellerPhone2 = '09127277479',
    this.cardNumber = '',
    this.shaba = '',
    this.smsHour = 9,
    this.smsMinute = 0,
    this.autoBackup = true,
    this.completionSmsTemplate = '{نام} عزیز، از اعتماد شما به کارنوپلاس متشکریم. خدمات انجام‌شده برای {دستگاه}: {شرح}. سرویس دوره‌ای بعدی در تاریخ {تاریخ} است و در موعد مقرر به شما یادآوری می‌کنیم.',
  });
  String sellerName, sellerPhone1, sellerPhone2, cardNumber, shaba, completionSmsTemplate;
  int smsHour, smsMinute;
  bool autoBackup;
  Map<String, dynamic> toJson() => {
        'sellerName': sellerName,
        'sellerPhone1': sellerPhone1,
        'sellerPhone2': sellerPhone2,
        'cardNumber': cardNumber,
        'shaba': shaba,
        'smsHour': smsHour,
        'smsMinute': smsMinute,
        'autoBackup': autoBackup,
        'completionSmsTemplate': completionSmsTemplate,
      };
  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        sellerName: j['sellerName']?.toString() ?? 'کارنوپلاس',
        sellerPhone1: j['sellerPhone1']?.toString() ?? '09123492589',
        sellerPhone2: j['sellerPhone2']?.toString() ?? '09127277479',
        cardNumber: j['cardNumber']?.toString() ?? '',
        shaba: j['shaba']?.toString() ?? '',
        smsHour: (j['smsHour'] as num?)?.toInt() ?? 9,
        smsMinute: (j['smsMinute'] as num?)?.toInt() ?? 0,
        autoBackup: j['autoBackup'] != false,
        completionSmsTemplate: j['completionSmsTemplate']?.toString() ?? '{نام} عزیز، از اعتماد شما به کارنوپلاس متشکریم. خدمات انجام‌شده برای {دستگاه}: {شرح}. سرویس دوره‌ای بعدی در تاریخ {تاریخ} است و در موعد مقرر به شما یادآوری می‌کنیم.',
      );
}

class SmsTemplate {
  SmsTemplate({required this.id, required this.title, required this.body});
  String id, title, body;
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'body': body};
  factory SmsTemplate.fromJson(Map<String, dynamic> j) => SmsTemplate(id: j['id']?.toString() ?? '', title: j['title']?.toString() ?? '', body: j['body']?.toString() ?? '');
}

class ServiceRecord {
  ServiceRecord({required this.id, required this.date, required this.description, required this.amount, this.nextDate = '', this.deviceId = ''});
  String id, date, description, nextDate, deviceId;
  double amount;
  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'description': description, 'amount': amount, 'nextDate': nextDate, 'deviceId': deviceId};
  factory ServiceRecord.fromJson(Map<String, dynamic> j) => ServiceRecord(
        id: j['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
        date: j['date']?.toString() ?? '', description: j['description']?.toString() ?? '', amount: (j['amount'] as num?)?.toDouble() ?? 0, nextDate: j['nextDate']?.toString() ?? '', deviceId: j['deviceId']?.toString() ?? '');
}

class PaymentRecord {
  PaymentRecord({required this.id, required this.date, required this.amount, this.note = ''});
  String id, date, note;
  double amount;
  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'amount': amount, 'note': note};
  factory PaymentRecord.fromJson(Map<String, dynamic> j) => PaymentRecord(
        id: j['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(), date: j['date']?.toString() ?? '', amount: (j['amount'] as num?)?.toDouble() ?? 0, note: j['note']?.toString() ?? '');
}

class InvoiceItem {
  InvoiceItem({required this.description, double? amount, this.quantity = 1, double? unitPrice})
      : unitPrice = unitPrice ?? amount ?? 0;
  String description;
  double quantity, unitPrice;
  double get amount => quantity * unitPrice;
  Map<String, dynamic> toJson() => {
        'description': description,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'amount': amount,
      };
  factory InvoiceItem.fromJson(Map<String, dynamic> j) {
    final legacyAmount = (j['amount'] as num?)?.toDouble() ?? 0;
    final q = (j['quantity'] as num?)?.toDouble() ?? 1;
    final up = (j['unitPrice'] as num?)?.toDouble() ?? (q == 0 ? legacyAmount : legacyAmount / q);
    return InvoiceItem(description: j['description']?.toString() ?? '', quantity: q == 0 ? 1 : q, unitPrice: up);
  }
}

class InvoiceRecord {
  InvoiceRecord({
    required this.id, required this.date, required this.title, required this.items,
    this.notes = '', this.sellerName = '', this.sellerPhone1 = '', this.sellerPhone2 = '', this.cardNumber = '', this.shaba = '',
    this.documentType = 'invoice', this.documentNumber = '', this.validUntil = '', this.discountType = 'amount',
    this.discountValue = 0, this.status = 'open', this.convertedToInvoiceId = '', this.internalName = '',
  });
  String id, date, title, notes, sellerName, sellerPhone1, sellerPhone2, cardNumber, shaba;
  String documentType, documentNumber, validUntil, discountType, status, convertedToInvoiceId, internalName;
  double discountValue;
  List<InvoiceItem> items;
  double get subtotal => items.fold(0, (s, e) => s + e.amount);
  double get discountAmount => discountType == 'percent'
      ? (subtotal * discountValue.clamp(0, 100) / 100)
      : discountValue.clamp(0, subtotal);
  double get total => (subtotal - discountAmount).clamp(0, double.infinity);
  bool get isProforma => documentType == 'proforma';
  String get typeLabel => isProforma ? 'پیش‌فاکتور' : 'فاکتور';
  String get statusLabel {
    if (status == 'paid') return 'تسویه‌شده';
    if (status == 'converted') return 'تبدیل‌شده به فاکتور';
    return isProforma ? 'باز' : 'تسویه‌نشده';
  }
  Map<String, dynamic> toJson() => {
        'id': id, 'date': date, 'title': title, 'notes': notes, 'sellerName': sellerName, 'sellerPhone1': sellerPhone1,
        'sellerPhone2': sellerPhone2, 'cardNumber': cardNumber, 'shaba': shaba, 'items': items.map((e) => e.toJson()).toList(),
        'documentType': documentType, 'documentNumber': documentNumber, 'validUntil': validUntil,
        'discountType': discountType, 'discountValue': discountValue, 'status': status, 'convertedToInvoiceId': convertedToInvoiceId, 'internalName': internalName,
      };
  factory InvoiceRecord.fromJson(Map<String, dynamic> j) => InvoiceRecord(
        id: j['id']?.toString() ?? '', date: j['date']?.toString() ?? '', title: j['title']?.toString() ?? 'فاکتور خدمات', notes: j['notes']?.toString() ?? '',
        sellerName: j['sellerName']?.toString() ?? '', sellerPhone1: j['sellerPhone1']?.toString() ?? '', sellerPhone2: j['sellerPhone2']?.toString() ?? '',
        cardNumber: j['cardNumber']?.toString() ?? '', shaba: j['shaba']?.toString() ?? '',
        documentType: j['documentType']?.toString() ?? 'invoice', documentNumber: j['documentNumber']?.toString() ?? '',
        validUntil: j['validUntil']?.toString() ?? '', discountType: j['discountType']?.toString() ?? 'amount',
        discountValue: (j['discountValue'] as num?)?.toDouble() ?? 0, status: j['status']?.toString() ?? 'open',
        convertedToInvoiceId: j['convertedToInvoiceId']?.toString() ?? '', internalName: j['internalName']?.toString() ?? j['title']?.toString() ?? '',
        items: ((j['items'] as List?) ?? []).map((e) => InvoiceItem.fromJson(Map<String, dynamic>.from(e))).toList());
}


class DeviceRecord {
  DeviceRecord({required this.id, required this.name, this.notes='', this.nextServiceDate='', this.smsTemplateId='', this.customSms=''});
  String id,name,notes,nextServiceDate,smsTemplateId,customSms;
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'notes':notes,'nextServiceDate':nextServiceDate,'smsTemplateId':smsTemplateId,'customSms':customSms};
  factory DeviceRecord.fromJson(Map<String,dynamic> j)=>DeviceRecord(
    id:j['id']?.toString()??newId(),name:j['name']?.toString()??'',notes:j['notes']?.toString()??'',
    nextServiceDate:j['nextServiceDate']?.toString()??'',smsTemplateId:j['smsTemplateId']?.toString()??'',customSms:j['customSms']?.toString()??'');
}
List<DeviceRecord> _devicesFromJson(Map<String,dynamic> j){
  final raw=j['devices'];
  if(raw is List && raw.isNotEmpty)return raw.map((e)=>DeviceRecord.fromJson(Map<String,dynamic>.from(e))).toList();
  final name=(j['deviceType']??j['vehicle'])?.toString()??'';
  final next=j['nextServiceDate']?.toString()??'';
  if(name.isEmpty && next.isEmpty)return <DeviceRecord>[];
  return [DeviceRecord(id:'legacy-'+(j['id']?.toString()??newId()),name:name.isEmpty?'دستگاه اول':name,nextServiceDate:next,smsTemplateId:j['smsTemplateId']?.toString()??'',customSms:j['customSms']?.toString()??'')];
}


class DailyTask {
  DailyTask({required this.id,required this.title,required this.date,this.notes='',this.done=false});
  String id,title,date,notes;
  bool done;
  Map<String,dynamic> toJson()=>{'id':id,'title':title,'date':date,'notes':notes,'done':done};
  factory DailyTask.fromJson(Map<String,dynamic> j)=>DailyTask(
    id:j['id']?.toString()??newId(),title:j['title']?.toString()??'',date:j['date']?.toString()??today(),
    notes:j['notes']?.toString()??'',done:j['done']==true);
}

class Customer {
  Customer({required this.id, required this.name, this.phone = '', this.address = '', this.deviceType = '', this.notes = '', this.nextServiceDate = '', this.smsTemplateId = '', this.customSms = '', List<DeviceRecord>? devices, List<ServiceRecord>? services, List<PaymentRecord>? payments, List<InvoiceRecord>? invoices})
      : devices = devices ?? [], services = services ?? [], payments = payments ?? [], invoices = invoices ?? [];
  String id, name, phone, address, deviceType, notes, nextServiceDate, smsTemplateId, customSms;
  List<DeviceRecord> devices;
  List<ServiceRecord> services;
  List<PaymentRecord> payments;
  List<InvoiceRecord> invoices;
  double get totalServices => services.fold(0, (s, e) => s + e.amount);
  double get totalInvoices => invoices.where((e) => !e.isProforma).fold(0, (s, e) => s + e.total);
  double get totalPayments => payments.fold(0, (s, e) => s + e.amount);
  double get balance => totalInvoices - totalPayments;
  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'phone': phone, 'address': address, 'deviceType': deviceType, 'vehicle': deviceType, 'notes': notes,
        'nextServiceDate': nextServiceDate, 'smsTemplateId': smsTemplateId, 'customSms': customSms, 'devices':devices.map((e)=>e.toJson()).toList(),
        'services': services.map((e) => e.toJson()).toList(), 'payments': payments.map((e) => e.toJson()).toList(), 'invoices': invoices.map((e) => e.toJson()).toList(),
      };
  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id']?.toString() ?? '', name: j['name']?.toString() ?? '', phone: j['phone']?.toString() ?? '', address: j['address']?.toString() ?? '',
        deviceType: (j['deviceType'] ?? j['vehicle'])?.toString() ?? '', notes: j['notes']?.toString() ?? '', nextServiceDate: j['nextServiceDate']?.toString() ?? '',
        smsTemplateId: j['smsTemplateId']?.toString() ?? '', customSms: j['customSms']?.toString() ?? '', devices:_devicesFromJson(j),
        services: ((j['services'] as List?) ?? []).map((e) => ServiceRecord.fromJson(Map<String, dynamic>.from(e))).toList(),
        payments: ((j['payments'] as List?) ?? []).map((e) => PaymentRecord.fromJson(Map<String, dynamic>.from(e))).toList(),
        invoices: ((j['invoices'] as List?) ?? []).map((e) => InvoiceRecord.fromJson(Map<String, dynamic>.from(e))).toList());
}

List<SmsTemplate> defaultSmsTemplates() => [
  SmsTemplate(id: 'general', title: 'عمومی', body: '{نام} عزیز، زمان سرویس دوره‌ای {دستگاه} در تاریخ {تاریخ} فرا رسیده است. کارنوپلاس'),
  SmsTemplate(id: 'filter', title: 'سرویس فیلتر', body: '{نام} عزیز، یادآوری سرویس {دستگاه}: لطفاً برای بررسی و سرویس در تاریخ {تاریخ} اقدام کنید. کارنوپلاس'),
  SmsTemplate(id: 'maintenance', title: 'سرویس و نگهداری', body: '{نام} گرامی، موعد سرویس و نگهداری {دستگاه} شما در تاریخ {تاریخ} است. کارنوپلاس'),
];

String renderSms(String body, Customer c) => body.replaceAll('{نام}', c.name).replaceAll('{دستگاه}', c.deviceType).replaceAll('{تاریخ}', c.nextServiceDate);
String today() { final j = Jalali.now(); return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}'; }
String money(double v) => '${v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')} تومان';
String newId() => DateTime.now().microsecondsSinceEpoch.toString();

String renderDeviceSms(String body,Customer c,DeviceRecord d)=>body.replaceAll('{نام}',c.name).replaceAll('{دستگاه}',d.name).replaceAll('{تاریخ}',d.nextServiceDate);
String renderCompletionSms(String body,Customer c,DeviceRecord d,String description,String nextDate)=>body.replaceAll('{نام}',c.name).replaceAll('{دستگاه}',d.name).replaceAll('{شرح}',description).replaceAll('{تاریخ}',nextDate.trim().isEmpty?'ثبت نشده':nextDate.trim());
int alarmIdFor(Customer c,DeviceRecord d)=>(c.id+':'+d.id).hashCode & 0x7fffffff;
String nearestService(Customer c){final a=c.devices.map((d)=>d.nextServiceDate).where((e)=>e.isNotEmpty).toList()..sort();return a.isEmpty?'':a.first;}


DateTime? parseServiceDate(String s, AppSettings settings) {
  try {
    final p = s.trim().replaceAll('-', '/').split('/');
    if (p.length != 3) return null;
    final g = Jalali(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])).toGregorian();
    return DateTime(g.year, g.month, g.day, settings.smsHour, settings.smsMinute);
  } catch (_) { return null; }
}

class HomeScreen extends StatefulWidget { const HomeScreen({super.key}); @override State<HomeScreen> createState() => _HomeScreenState(); }
class _HomeScreenState extends State<HomeScreen> {
  final List<Customer> customers = [];
  final List<SmsTemplate> templates = [];
  final List<DailyTask> tasks = [];
  AppSettings settings = AppSettings();
  final search = TextEditingController();
  bool loading = true;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { search.dispose(); super.dispose(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    try { final r = p.getString(_storageKey); if (r != null) customers.addAll((jsonDecode(r) as List).map((e) => Customer.fromJson(Map<String,dynamic>.from(e)))); } catch (_) {}
    try { final r = p.getString(_templatesKey); if (r != null) templates.addAll((jsonDecode(r) as List).map((e) => SmsTemplate.fromJson(Map<String,dynamic>.from(e)))); } catch (_) {}
    try { final r = p.getString(_settingsKey); if (r != null) settings = AppSettings.fromJson(Map<String,dynamic>.from(jsonDecode(r))); } catch (_) {}
    try { final r = p.getString(_tasksKey); if (r != null) tasks.addAll((jsonDecode(r) as List).map((e)=>DailyTask.fromJson(Map<String,dynamic>.from(e)))); } catch (_) {}
    if (templates.isEmpty) templates.addAll(defaultSmsTemplates());
    for (final c in customers) { if(c.smsTemplateId.isEmpty)c.smsTemplateId=templates.first.id; for(final d in c.devices){if(d.smsTemplateId.isEmpty)d.smsTemplateId=templates.first.id;} }
    await _saveCore(dailyBackup: true);
    await _scheduleAll();
    if (mounted) setState(() => loading = false);
  }

  Map<String,dynamic> _fullBackup() => {'version': 3, 'createdAt': DateTime.now().toIso8601String(), 'customers': customers.map((e)=>e.toJson()).toList(), 'templates': templates.map((e)=>e.toJson()).toList(), 'settings': settings.toJson(), 'tasks': tasks.map((e)=>e.toJson()).toList()};

  Future<void> _saveCore({bool dailyBackup = true}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_storageKey, jsonEncode(customers.map((e)=>e.toJson()).toList()));
    await p.setString(_templatesKey, jsonEncode(templates.map((e)=>e.toJson()).toList()));
    await p.setString(_settingsKey, jsonEncode(settings.toJson()));
    await p.setString(_tasksKey, jsonEncode(tasks.map((e)=>e.toJson()).toList()));
    if (dailyBackup && settings.autoBackup) {
      final key = DateTime.now().toIso8601String().substring(0,10);
      if (p.getString(_dailyBackupKey) != key) {
        try {
          final ok = await _channel.invokeMethod<bool>('saveBackup', {'json': jsonEncode(_fullBackup()), 'fileName': 'modiriat-service-$key.json'});
          if (ok == true) await p.setString(_dailyBackupKey, key);
        } catch (_) {}
      }
    }
    if (mounted) setState(() {});
  }

  SmsTemplate templateFor(Customer c)=>templates.firstWhere((e)=>e.id==c.smsTemplateId,orElse:()=>templates.first);
  SmsTemplate templateForDevice(DeviceRecord d)=>templates.firstWhere((e)=>e.id==d.smsTemplateId,orElse:()=>templates.first);
  String smsFor(Customer c)=>renderSms(c.customSms.trim().isNotEmpty?c.customSms:templateFor(c).body,c);
  String smsForDevice(Customer c,DeviceRecord d)=>renderDeviceSms(d.customSms.trim().isNotEmpty?d.customSms:templateForDevice(d).body,c,d);

  Future<void> _scheduleDevice(Customer c,DeviceRecord d) async {
    if(!settings.smsEnabled||c.phone.trim().isEmpty||d.nextServiceDate.trim().isEmpty)return;
    final when=parseServiceDate(d.nextServiceDate,settings);
    if(when==null||when.isBefore(DateTime.now())||!(await Permission.sms.status).isGranted)return;
    try{await _channel.invokeMethod('scheduleSms',{'id':alarmIdFor(c,d),'phone':c.phone.trim(),'message':smsForDevice(c,d),'timeMillis':when.millisecondsSinceEpoch});}catch(_){}
  }
  Future<void> _schedule(Customer c) async {
    try{await _channel.invokeMethod('cancelSms',{'id':c.id.hashCode & 0x7fffffff});}catch(_){}
    for(final d in c.devices){await _scheduleDevice(c,d);}
  }
  Future<void> _scheduleAll() async {for(final c in customers){await _schedule(c);}}
  Future<void> _cancelAllSms() async {for(final c in customers){try{await _channel.invokeMethod('cancelSms',{'id':c.id.hashCode & 0x7fffffff});}catch(_){} for(final d in c.devices){try{await _channel.invokeMethod('cancelSms',{'id':alarmIdFor(c,d)});}catch(_){}}}}
  Future<void> _setSmsEnabled(bool enabled) async {
    if(enabled==settings.smsEnabled)return;
    if(!enabled){settings.smsEnabled=false;settings.smsPausedAt=DateTime.now().toIso8601String();await _cancelAllSms();await _saveCore(dailyBackup:false);return;}
    final pausedAt=DateTime.tryParse(settings.smsPausedAt);settings.smsEnabled=true;settings.smsPausedAt='';await _saveCore(dailyBackup:false);
    if(!(await Permission.sms.status).isGranted)return;
    final now=DateTime.now();
    for(final c in customers){if(c.phone.trim().isEmpty)continue;for(final d in c.devices){
      final when=parseServiceDate(d.nextServiceDate,settings);if(when==null)continue;
      if(pausedAt!=null&&!when.isBefore(pausedAt)&&!when.isAfter(now)){try{await _channel.invokeMethod('sendSmsNow',{'phone':c.phone.trim(),'message':smsForDevice(c,d)});}catch(_){}}
      else if(when.isAfter(now)){await _scheduleDevice(c,d);}
    }}
  }

  List<Customer> get filtered {
    final q=search.text.trim().toLowerCase(); if(q.isEmpty)return customers;
    return customers.where((c)=>[c.name,c.phone,c.deviceType,c.address].any((x)=>x.toLowerCase().contains(q))).toList();
  }

  Future<void> _customerForm({Customer? customer}) async {
    final name=TextEditingController(text:customer?.name??''),phone=TextEditingController(text:customer?.phone??''),address=TextEditingController(text:customer?.address??''),notes=TextEditingController(text:customer?.notes??'');
    final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:Text(customer==null?'مشتری جدید':'ویرایش مشتری'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      _field(name,'نام مشتری'),const SizedBox(height:8),_field(phone,'شماره تماس',type:TextInputType.phone),const SizedBox(height:8),_field(address,'آدرس',lines:2),const SizedBox(height:8),_field(notes,'توضیحات',lines:2)
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('ذخیره'))]));
    if(ok!=true||name.text.trim().isEmpty)return;final c=customer??Customer(id:newId(),name:name.text.trim());
    c..name=name.text.trim()..phone=phone.text.trim()..address=address.text.trim()..notes=notes.text.trim();if(customer==null)customers.insert(0,c);await _saveCore();await _schedule(c);
  }

  Future<void> _backupDialog() async {
    await showDialog(context:context,builder:(d)=>AlertDialog(title:const Text('بکاپ و بازیابی'),content:const Text('بکاپ دستی در پوشه Download/ModiriatService ذخیره می‌شود. بکاپ خودکار نیز روزی یک‌بار هنگام باز شدن برنامه انجام می‌شود.'),actions:[
      TextButton(onPressed:()async{await Clipboard.setData(ClipboardData(text:jsonEncode(_fullBackup())));if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('بکاپ در کلیپ‌بورد کپی شد')));},child:const Text('کپی بکاپ')),
      TextButton(onPressed:()async{try{final ok=await _channel.invokeMethod<bool>('saveBackup',{'json':jsonEncode(_fullBackup()),'fileName':'modiriat-service-manual-${DateTime.now().millisecondsSinceEpoch}.json'});if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(ok==true?'بکاپ در Downloads ذخیره شد':'ذخیره بکاپ انجام نشد')));}catch(_){ }},child:const Text('ذخیره در Downloads')),
      FilledButton(onPressed:()async{final clip=await Clipboard.getData('text/plain');try{final j=jsonDecode(clip?.text??'');final map=Map<String,dynamic>.from(j);customers..clear()..addAll((map['customers'] as List).map((e)=>Customer.fromJson(Map<String,dynamic>.from(e))));if(map['templates'] is List){templates..clear()..addAll((map['templates'] as List).map((e)=>SmsTemplate.fromJson(Map<String,dynamic>.from(e))));}if(map['settings'] is Map)settings=AppSettings.fromJson(Map<String,dynamic>.from(map['settings']));if(map['tasks'] is List){tasks..clear()..addAll((map['tasks'] as List).map((e)=>DailyTask.fromJson(Map<String,dynamic>.from(e))));}await _saveCore();await _scheduleAll();if(d.mounted)Navigator.pop(d);}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('بکاپ معتبر نیست')));}},child:const Text('بازیابی از کلیپ‌بورد'))
    ]));
  }

  int get _dueWorkCount {
    var count=tasks.where((t)=>!t.done&&t.date.isNotEmpty&&t.date.compareTo(today())<=0).length;
    for(final c in customers){for(final d in c.devices){if(d.nextServiceDate.isNotEmpty&&d.nextServiceDate.compareTo(today())<=0)count++;}}
    return count;
  }

  Future<void> _dailyTasks() async {
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>DailyTasksScreen(customers:customers,tasks:tasks,onSave:_saveCore)));
    if(mounted)setState((){});
  }

  Future<void> _settings() async { await Navigator.push(context,MaterialPageRoute(builder:(_)=>SettingsScreen(settings:settings,templates:templates,onSave:()async{await _saveCore();await _scheduleAll();}))); if(mounted)setState((){}); }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('کارنوپلاس | مدیریت سرویس',style:TextStyle(fontWeight:FontWeight.w800)),actions:[IconButton(onPressed:_backupDialog,icon:const Icon(Icons.backup_outlined),tooltip:'بکاپ'),IconButton(onPressed:_settings,icon:const Icon(Icons.settings_outlined),tooltip:'تنظیمات')]),
    floatingActionButton:FloatingActionButton.extended(onPressed:()=>_customerForm(),icon:const Icon(Icons.person_add_alt_1),label:const Text('مشتری جدید')),
    body:loading?const Center(child:CircularProgressIndicator()):Column(children:[
      Container(margin:const EdgeInsets.fromLTRB(16,8,16,12),padding:const EdgeInsets.all(16),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF0F766E),Color(0xFF115E59)]),borderRadius:BorderRadius.circular(22)),child:Row(children:[Expanded(child:_stat('مشتری',customers.length.toString())),Expanded(child:_stat('طلب کل',money(customers.fold(0.0,(s,c)=>s+(c.balance>0?c.balance:0)))))])),
      Padding(padding:const EdgeInsets.fromLTRB(16,0,16,10),child:FilledButton.tonalIcon(onPressed:_dailyTasks,icon:const Icon(Icons.event_note_outlined),label:Text(_dueWorkCount>0?'کارهای روزانه • $_dueWorkCount مورد نیاز به پیگیری':'کارهای روزانه'))),
      Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:TextField(controller:search,onChanged:(_)=>setState((){}),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'جستجو نام، شماره، دستگاه یا آدرس...'))),const SizedBox(height:10),
      Expanded(child:filtered.isEmpty?const Center(child:Text('هنوز مشتری ثبت نشده')):ListView.separated(padding:const EdgeInsets.fromLTRB(16,0,16,100),itemCount:filtered.length,separatorBuilder:(_,__)=>const SizedBox(height:10),itemBuilder:(ctx,i){final c=filtered[i];return Card(child:ListTile(contentPadding:const EdgeInsets.all(14),leading:CircleAvatar(child:Text(c.name.isEmpty?'?':c.name.substring(0,1))),title:Text(c.name,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text([if(c.phone.isNotEmpty)c.phone,'تعداد دستگاه: ${c.devices.length}',if(nearestService(c).isNotEmpty)'نزدیک‌ترین سرویس: ${nearestService(c)}','مانده: ${money(c.balance)}'].join('\n')),trailing:const Icon(Icons.chevron_left),onTap:()async{await Navigator.push(context,MaterialPageRoute(builder:(_)=>CustomerScreen(customer:c,templates:templates,settings:settings,onSave:_saveCore,onSchedule:_schedule,onEditCustomer:()=>_customerForm(customer:c))));if(mounted)setState((){});}));}))
    ]));

  Widget _stat(String a,String b)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(a,style:const TextStyle(color:Colors.white70)),const SizedBox(height:4),Text(b,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold,fontSize:18))]);
}


class DailyTasksScreen extends StatefulWidget{
  const DailyTasksScreen({super.key,required this.customers,required this.tasks,required this.onSave});
  final List<Customer> customers; final List<DailyTask> tasks; final Future<void> Function({bool dailyBackup}) onSave;
  @override State<DailyTasksScreen> createState()=>_DailyTasksScreenState();
}
class _DailyTasksScreenState extends State<DailyTasksScreen>{
  Future<void> _taskForm({DailyTask? task})async{
    final title=TextEditingController(text:task?.title??''),date=TextEditingController(text:task?.date??today()),notes=TextEditingController(text:task?.notes??'');
    final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:Text(task==null?'کار جدید':'ویرایش کار'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      _field(title,'عنوان کار'),const SizedBox(height:8),_field(date,'تاریخ انجام'),const SizedBox(height:8),_field(notes,'توضیحات',lines:3)
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('ذخیره'))]));
    if(ok!=true||title.text.trim().isEmpty)return;
    final t=task??DailyTask(id:newId(),title:title.text.trim(),date:date.text.trim());
    t..title=title.text.trim()..date=date.text.trim()..notes=notes.text.trim();
    if(task==null)widget.tasks.add(t);await widget.onSave();if(mounted)setState((){});
  }
  List<Map<String,dynamic>> get _items{
    final out=<Map<String,dynamic>>[];
    for(final t in widget.tasks){out.add({'date':t.date,'type':'task','task':t});}
    for(final c in widget.customers){for(final d in c.devices){if(d.nextServiceDate.isNotEmpty)out.add({'date':d.nextServiceDate,'type':'service','customer':c,'device':d});}}
    out.sort((a,b)=>(a['date'] as String).compareTo(b['date'] as String));
    return out;
  }
  String _state(String date,bool done){if(done)return'انجام‌شده';if(date.compareTo(today())<0)return'عقب‌افتاده';if(date==today())return'امروز';return'آینده';}
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('کارهای روزانه')),
    floatingActionButton:FloatingActionButton.extended(onPressed:()=>_taskForm(),icon:const Icon(Icons.add_task),label:const Text('کار جدید')),
    body:ListView(padding:const EdgeInsets.fromLTRB(16,12,16,100),children:[
      Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(16)),child:const Text('سرویس‌های دوره‌ای مشتری‌ها خودکار اینجا نمایش داده می‌شوند. کارهای هماهنگی، خرید، تماس و پیگیری را هم می‌توانید دستی اضافه کنید.')),
      const SizedBox(height:12),
      ..._items.map((m){
        final isTask=m['type']=='task';
        if(isTask){
          final t=m['task'] as DailyTask;
          return Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(
            leading:Checkbox(value:t.done,onChanged:(v)async{t.done=v==true;await widget.onSave();if(mounted)setState((){});}),
            title:Text(t.title,style:TextStyle(fontWeight:FontWeight.w700,decoration:t.done?TextDecoration.lineThrough:null)),
            subtitle:Text('${t.date} • ${_state(t.date,t.done)}${t.notes.isEmpty?'':'\n${t.notes}'}'),
            trailing:IconButton(onPressed:()=>_taskForm(task:t),icon:const Icon(Icons.edit_outlined))
          ));
        }
        final c=m['customer'] as Customer,d=m['device'] as DeviceRecord,date=m['date'] as String;
        return Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(
          leading:const CircleAvatar(child:Icon(Icons.build_outlined)),
          title:Text('سرویس دوره‌ای • ${c.name}',style:const TextStyle(fontWeight:FontWeight.w700)),
          subtitle:Text('${d.name}\n$date • ${_state(date,false)}'),
          isThreeLine:true
        ));
      })
    ])
  );
}

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key,required this.customer,required this.templates,required this.settings,required this.onSave,required this.onSchedule,required this.onEditCustomer});
  final Customer customer; final List<SmsTemplate> templates; final AppSettings settings; final Future<void> Function({bool dailyBackup}) onSave; final Future<void> Function(Customer) onSchedule; final Future<void> Function() onEditCustomer;
  @override State<CustomerScreen> createState()=>_CustomerScreenState();
}
class _CustomerScreenState extends State<CustomerScreen>{
  Customer get c=>widget.customer;
  Future<void> _save()async{await widget.onSave();if(mounted)setState((){});}

  DeviceRecord? _deviceById(String id){for(final d in c.devices){if(d.id==id)return d;}return null;}

  Future<void> _deviceForm({DeviceRecord? device}) async {
    final name=TextEditingController(text:device?.name??''),next=TextEditingController(text:device?.nextServiceDate??''),notes=TextEditingController(text:device?.notes??'');
    var tpl=device?.smsTemplateId.isNotEmpty==true?device!.smsTemplateId:widget.templates.first.id;
    final ok=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:Text(device==null?'افزودن دستگاه':'ویرایش دستگاه'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      _field(name,'نام / نوع دستگاه'),const SizedBox(height:8),_field(next,'تاریخ سرویس بعدی',hint:'مثلاً 1405/09/10'),const SizedBox(height:8),
      DropdownButtonFormField<String>(value:tpl,decoration:const InputDecoration(labelText:'قالب پیامک'),items:widget.templates.map((e)=>DropdownMenuItem(value:e.id,child:Text(e.title))).toList(),onChanged:(v){if(v!=null)setD(()=>tpl=v);}),const SizedBox(height:8),_field(notes,'توضیحات دستگاه',lines:2)
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('ذخیره'))])));
    if(ok!=true||name.text.trim().isEmpty)return;final dev=device??DeviceRecord(id:newId(),name:name.text.trim());
    dev..name=name.text.trim()..nextServiceDate=next.text.trim()..notes=notes.text.trim()..smsTemplateId=tpl;if(device==null)c.devices.add(dev);await _save();await widget.onSchedule(c);
  }

  Future<void> _deviceSmsEditor(DeviceRecord d) async {
    final tpl=widget.templates.firstWhere((e)=>e.id==d.smsTemplateId,orElse:()=>widget.templates.first);
    final ctrl=TextEditingController(text:d.customSms.isNotEmpty?d.customSms:tpl.body);
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(title:Text('پیامک ${d.name}'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      Text('پیش‌نمایش: ${renderDeviceSms(ctrl.text,c,d)}'),const SizedBox(height:10),TextField(controller:ctrl,maxLines:6,onChanged:(_)=>setD((){}),decoration:const InputDecoration(labelText:'متن پیامک',helperText:'متغیرها: {نام} {دستگاه} {تاریخ}'))
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('ذخیره و زمان‌بندی'))])));
    if(ok==true){d.customSms=ctrl.text.trim();await _save();await widget.onSchedule(c);}
  }

  bool _inRange(String date,String from,String to){final v=date.replaceAll('-','/'),a=from.replaceAll('-','/'),b=to.replaceAll('-','/');return v.isNotEmpty&&v.compareTo(a)>=0&&v.compareTo(b)<=0;}

  Future<void> _reportDialog() async {
    final from=TextEditingController(text:'${Jalali.now().year}/01/01'),to=TextEditingController(text:today());String deviceId='';
    final ok=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:const Text('گزارش عملکرد'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      _field(from,'از تاریخ'),const SizedBox(height:8),_field(to,'تا تاریخ'),const SizedBox(height:8),
      DropdownButtonFormField<String>(value:deviceId,decoration:const InputDecoration(labelText:'دستگاه'),items:[const DropdownMenuItem(value:'',child:Text('همه دستگاه‌ها')),...c.devices.map((e)=>DropdownMenuItem(value:e.id,child:Text(e.name)))],onChanged:(v)=>setD(()=>deviceId=v??''))
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton.icon(onPressed:()=>Navigator.pop(d,true),icon:const Icon(Icons.picture_as_pdf),label:const Text('ساخت PDF'))])));
    if(ok==true)await _reportPdf(from.text.trim(),to.text.trim(),deviceId);
  }

  Future<void> _reportPdf(String from,String to,String deviceId) async {
    final services=c.services.where((s)=>_inRange(s.date,from,to)&&(deviceId.isEmpty||s.deviceId==deviceId||(s.deviceId.isEmpty&&c.devices.isNotEmpty&&c.devices.first.id==deviceId))).toList();
    final payments=c.payments.where((p)=>_inRange(p.date,from,to)).toList();
    final ts=services.fold<double>(0,(a,e)=>a+e.amount),tp=payments.fold<double>(0,(a,e)=>a+e.amount),sel=deviceId.isEmpty?null:_deviceById(deviceId);
    final font=await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'),f=pw.Font.ttf(font);final doc=pw.Document();
    doc.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.all(28),theme:pw.ThemeData.withFont(base:f,bold:f),textDirection:pw.TextDirection.rtl,build:(ctx)=>[
      pw.Container(padding:const pw.EdgeInsets.all(16),decoration:pw.BoxDecoration(color:PdfColors.teal50,border:pw.Border.all(color:PdfColors.teal300),borderRadius:pw.BorderRadius.circular(8)),child:pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[
        pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[pw.Text(widget.settings.sellerName.isEmpty?'کارنوپلاس':widget.settings.sellerName,style:pw.TextStyle(fontSize:22,fontWeight:pw.FontWeight.bold)),pw.Text('گزارش عملکرد مشتری',style:pw.TextStyle(fontSize:15,fontWeight:pw.FontWeight.bold))]),
        pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.end,children:[pw.Text('از $from'),pw.Text('تا $to')])
      ])),
      pw.SizedBox(height:14),
      pw.Container(padding:const pw.EdgeInsets.all(12),decoration:pw.BoxDecoration(border:pw.Border.all(color:PdfColors.grey400),borderRadius:pw.BorderRadius.circular(6)),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:[
        pw.Text('نام مشتری: ${c.name}',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),if(c.phone.isNotEmpty)pw.Text('شماره تماس: ${c.phone}'),if(c.address.isNotEmpty)pw.Text('آدرس: ${c.address}'),pw.Text('دستگاه: ${sel?.name ?? 'همه دستگاه‌ها'}')
      ])),
      pw.SizedBox(height:16),
      pw.Row(children:[
        pw.Expanded(child:pw.Container(padding:const pw.EdgeInsets.all(10),decoration:pw.BoxDecoration(color:PdfColors.grey100,borderRadius:pw.BorderRadius.circular(5)),child:pw.Column(children:[pw.Text('جمع خدمات'),pw.Text(money(ts),style:pw.TextStyle(fontWeight:pw.FontWeight.bold))]))),
        pw.SizedBox(width:8),pw.Expanded(child:pw.Container(padding:const pw.EdgeInsets.all(10),decoration:pw.BoxDecoration(color:PdfColors.grey100,borderRadius:pw.BorderRadius.circular(5)),child:pw.Column(children:[pw.Text('جمع پرداختی'),pw.Text(money(tp),style:pw.TextStyle(fontWeight:pw.FontWeight.bold))]))),
        pw.SizedBox(width:8),pw.Expanded(child:pw.Container(padding:const pw.EdgeInsets.all(10),decoration:pw.BoxDecoration(color:PdfColors.teal50,borderRadius:pw.BorderRadius.circular(5)),child:pw.Column(children:[pw.Text('مانده بازه'),pw.Text(money(ts-tp),style:pw.TextStyle(fontWeight:pw.FontWeight.bold))])))
      ]),
      pw.SizedBox(height:18),pw.Text('خدمات انجام‌شده',style:pw.TextStyle(fontSize:15,fontWeight:pw.FontWeight.bold)),pw.SizedBox(height:6),
      if(services.isEmpty)pw.Container(padding:const pw.EdgeInsets.all(12),child:pw.Text('در این بازه خدمتی ثبت نشده است.')) else pw.TableHelper.fromTextArray(
        headers:['ردیف','تاریخ','دستگاه','شرح خدمت','مبلغ'],
        data:services.asMap().entries.map((e){final s=e.value;final dn=_deviceById(s.deviceId)?.name??(c.devices.isNotEmpty?c.devices.first.name:'');return ['${e.key+1}',s.date,dn,s.description,money(s.amount)];}).toList(),
        headerDecoration:const pw.BoxDecoration(color:PdfColors.teal50),headerStyle:pw.TextStyle(fontWeight:pw.FontWeight.bold),border:pw.TableBorder.all(color:PdfColors.grey400),cellAlignment:pw.Alignment.centerRight,cellPadding:const pw.EdgeInsets.all(6)),
      pw.SizedBox(height:18),pw.Text('پرداخت‌ها',style:pw.TextStyle(fontSize:15,fontWeight:pw.FontWeight.bold)),pw.SizedBox(height:6),
      if(payments.isEmpty)pw.Container(padding:const pw.EdgeInsets.all(12),child:pw.Text('در این بازه پرداختی ثبت نشده است.')) else pw.TableHelper.fromTextArray(
        headers:['ردیف','تاریخ','توضیحات','مبلغ'],data:payments.asMap().entries.map((e)=>['${e.key+1}',e.value.date,e.value.note,money(e.value.amount)]).toList(),
        headerDecoration:const pw.BoxDecoration(color:PdfColors.teal50),headerStyle:pw.TextStyle(fontWeight:pw.FontWeight.bold),border:pw.TableBorder.all(color:PdfColors.grey400),cellAlignment:pw.Alignment.centerRight,cellPadding:const pw.EdgeInsets.all(6)),
      pw.SizedBox(height:22),pw.Divider(color:PdfColors.grey400),pw.Align(alignment:pw.Alignment.centerLeft,child:pw.Text('کارنوپلاس | گزارش تولیدشده توسط مدیریت سرویس',style:const pw.TextStyle(fontSize:9,color:PdfColors.grey700)))
    ]));
    final bytes=await doc.save();await Printing.sharePdf(bytes:bytes,filename:'performance-${c.name}-${from.replaceAll('/','-')}-${to.replaceAll('/','-')}.pdf');
  }

  Future<void> _serviceForm({ServiceRecord? record}) async {
    if(c.devices.isEmpty){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('اول یک دستگاه ثبت کنید')));return;}
    final desc=TextEditingController(text:record?.description??''),amount=TextEditingController(text:record==null?'':groupDigits(record.amount.toStringAsFixed(0))),date=TextEditingController(text:record?.date??today()),next=TextEditingController(text:record?.nextDate??'');
    var deviceId=(record?.deviceId.isNotEmpty==true)?record!.deviceId:c.devices.first.id;if(!c.devices.any((d)=>d.id==deviceId))deviceId=c.devices.first.id;if(record==null)next.text=_deviceById(deviceId)?.nextServiceDate??'';
    var sendCompletion=false;
    final ok=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:Text(record==null?'ثبت سرویس':'ویرایش سرویس'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      DropdownButtonFormField<String>(value:deviceId,decoration:const InputDecoration(labelText:'دستگاه'),items:c.devices.map((e)=>DropdownMenuItem(value:e.id,child:Text(e.name))).toList(),onChanged:(v){if(v!=null)setD((){deviceId=v;if(record==null)next.text=_deviceById(v)?.nextServiceDate??'';});}),const SizedBox(height:8),
      _field(desc,'شرح سرویس'),const SizedBox(height:8),TextField(controller:amount,keyboardType:TextInputType.number,inputFormatters:[ThousandsSeparatorInputFormatter()],decoration:const InputDecoration(labelText:'مبلغ (تومان)',hintText:'مثلاً 1,250,000')),const SizedBox(height:8),_field(date,'تاریخ'),const SizedBox(height:8),_field(next,'سرویس بعدی'),const SizedBox(height:8),SwitchListTile(contentPadding:EdgeInsets.zero,value:sendCompletion,onChanged:(v)=>setD(()=>sendCompletion=v),title:const Text('ارسال پیام پایان کار به مشتری'),subtitle:const Text('تشکر + خلاصه کار + تاریخ سرویس بعدی'))
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('ذخیره'))])));
    if(ok!=true||desc.text.trim().isEmpty)return;final r=record??ServiceRecord(id:newId(),date:'',description:'',amount:0);
    r..description=desc.text.trim()..amount=double.tryParse(amount.text.replaceAll(',',''))??0..date=date.text.trim()..nextDate=next.text.trim()..deviceId=deviceId;if(record==null)c.services.insert(0,r);
    final dev=_deviceById(deviceId);if(dev!=null&&next.text.trim().isNotEmpty)dev.nextServiceDate=next.text.trim();await _save();await widget.onSchedule(c);
    if(sendCompletion&&dev!=null&&c.phone.trim().isNotEmpty){
      var permission=await Permission.sms.status;
      if(!permission.isGranted)permission=await Permission.sms.request();
      if(permission.isGranted){
        final msg=renderCompletionSms(widget.settings.completionSmsTemplate,c,dev,desc.text.trim(),next.text.trim());
        try{await _channel.invokeMethod('sendSmsNow',{'phone':c.phone.trim(),'message':msg});if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('پیام پایان کار برای مشتری ارسال شد')));}catch(_){}
      }else if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('برای ارسال پیام پایان کار، مجوز پیامک لازم است')));}
    }
  }

  Future<void> _paymentForm({PaymentRecord? record}) async {
    final amount=TextEditingController(text:record==null?'':groupDigits(record.amount.toStringAsFixed(0))),date=TextEditingController(text:record?.date??today()),note=TextEditingController(text:record?.note??'');
    final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:Text(record==null?'ثبت پرداخت':'ویرایش پرداخت'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:amount,keyboardType:TextInputType.number,inputFormatters:[ThousandsSeparatorInputFormatter()],decoration:const InputDecoration(labelText:'مبلغ (تومان)',hintText:'مثلاً 1,250,000')),const SizedBox(height:8),_field(date,'تاریخ'),const SizedBox(height:8),_field(note,'توضیحات')]),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('ذخیره'))]));
    if(ok!=true)return;final r=record??PaymentRecord(id:newId(),date:'',amount:0);r..amount=double.tryParse(amount.text.replaceAll(',',''))??0..date=date.text.trim()..note=note.text.trim();if(record==null)c.payments.insert(0,r);await _save();
  }

  String _nextDocumentNumber(String type){
    final prefix=type=='proforma'?'PF':'INV';
    final date=today().replaceAll('/','');
    final count=c.invoices.where((e)=>e.documentType==type).length+1;
    return '$prefix-$date-${count.toString().padLeft(3,'0')}';
  }

  Future<void> _invoiceForm({InvoiceRecord? invoice,String? documentType}) async {
    final type=invoice?.documentType??documentType??'invoice';
    final date=TextEditingController(text:invoice?.date??today()),
      internalName=TextEditingController(text:invoice?.internalName??''),
      title=TextEditingController(text:invoice?.title??(type=='proforma'?'پیش‌فاکتور خدمات':'فاکتور خدمات')),
      number=TextEditingController(text:invoice?.documentNumber.isNotEmpty==true?invoice!.documentNumber:_nextDocumentNumber(type)),
      validUntil=TextEditingController(text:invoice?.validUntil??''),
      notes=TextEditingController(text:invoice?.notes??''),
      seller=TextEditingController(text:invoice?.sellerName.isNotEmpty==true?invoice!.sellerName:widget.settings.sellerName),
      p1=TextEditingController(text:invoice?.sellerPhone1.isNotEmpty==true?invoice!.sellerPhone1:widget.settings.sellerPhone1),
      p2=TextEditingController(text:invoice?.sellerPhone2.isNotEmpty==true?invoice!.sellerPhone2:widget.settings.sellerPhone2),
      card=TextEditingController(text:invoice?.cardNumber.isNotEmpty==true?invoice!.cardNumber:widget.settings.cardNumber),
      shaba=TextEditingController(text:invoice?.shaba.isNotEmpty==true?invoice!.shaba:widget.settings.shaba),
      discount=TextEditingController(text:invoice==null||invoice.discountValue==0?'':(invoice.discountType=='amount'?groupDigits(invoice.discountValue.toStringAsFixed(0)):invoice.discountValue.toStringAsFixed(0)));
    var discountType=invoice?.discountType??'amount';var status=invoice?.status??'open';
    final items=(invoice?.items.map((e)=>InvoiceItem(description:e.description,quantity:e.quantity,unitPrice:e.unitPrice)).toList()??[InvoiceItem(description:'',quantity:1,unitPrice:0)]);
    final ok=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(
      title:Text(invoice==null?(type=='proforma'?'پیش‌فاکتور جدید':'فاکتور جدید'):'ویرایش ${invoice.typeLabel}'),
      content:SizedBox(width:560,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        _field(internalName,type=='proforma'?'نام پیش‌فاکتور (فقط داخل برنامه)':'نام فاکتور (فقط داخل برنامه)',hint:'مثلاً پروژه سعادت‌آباد'),const SizedBox(height:8),
        Row(children:[Expanded(child:_field(number,'شماره سند')),const SizedBox(width:8),Expanded(child:_field(date,'تاریخ'))]),const SizedBox(height:8),_field(title,'عنوان داخل سند',hint:type=='proforma'?'پیش‌فاکتور خدمات':'فاکتور خدمات'),
        if(type=='proforma')...[const SizedBox(height:8),_field(validUntil,'اعتبار تا',hint:'مثلاً 1405/09/30')],
        const SizedBox(height:8),DropdownButtonFormField<String>(value:status,decoration:const InputDecoration(labelText:'وضعیت سند'),items:[
          DropdownMenuItem(value:'open',child:Text(type=='proforma'?'باز':'تسویه‌نشده')),if(type=='invoice')const DropdownMenuItem(value:'paid',child:Text('تسویه‌شده')),if(type=='proforma'&&invoice?.status=='converted')const DropdownMenuItem(value:'converted',child:Text('تبدیل‌شده به فاکتور'))
        ],onChanged:(v){if(v!=null)setD(()=>status=v);}),
        const Divider(height:28),
        ...items.asMap().entries.map((e){
          final dc=TextEditingController(text:e.value.description),qc=TextEditingController(text:e.value.quantity.toStringAsFixed(e.value.quantity%1==0?0:1)),pc=TextEditingController(text:e.value.unitPrice==0?'':groupDigits(e.value.unitPrice.toStringAsFixed(0)));
          return Padding(padding:const EdgeInsets.only(bottom:10),child:Column(children:[
            Row(children:[Expanded(child:TextField(controller:dc,decoration:const InputDecoration(labelText:'شرح کالا / خدمت'),onChanged:(v)=>e.value.description=v)),IconButton(onPressed:items.length==1?null:()=>setD(()=>items.removeAt(e.key)),icon:const Icon(Icons.delete_outline))]),
            const SizedBox(height:6),Row(children:[
              SizedBox(width:90,child:TextField(controller:qc,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'تعداد'),onChanged:(v)=>e.value.quantity=double.tryParse(v)??1)),const SizedBox(width:6),
              Expanded(child:TextField(controller:pc,keyboardType:TextInputType.number,inputFormatters:[ThousandsSeparatorInputFormatter()],decoration:const InputDecoration(labelText:'فی واحد (تومان)'),onChanged:(v)=>e.value.unitPrice=double.tryParse(v.replaceAll(',',''))??0)),const SizedBox(width:6),
              Expanded(child:InputDecorator(decoration:const InputDecoration(labelText:'مبلغ ردیف'),child:Text(money(e.value.amount),style:const TextStyle(fontWeight:FontWeight.bold))))
            ])
          ]));
        }),
        Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:()=>setD(()=>items.add(InvoiceItem(description:'',quantity:1,unitPrice:0))),icon:const Icon(Icons.add),label:const Text('ردیف جدید'))),
        const Divider(height:24),Row(children:[
          Expanded(child:DropdownButtonFormField<String>(value:discountType,decoration:const InputDecoration(labelText:'نوع تخفیف'),items:const [DropdownMenuItem(value:'amount',child:Text('مبلغی')),DropdownMenuItem(value:'percent',child:Text('درصدی'))],onChanged:(v){if(v!=null)setD((){discountType=v;discount.clear();});})),
          const SizedBox(width:8),Expanded(child:TextField(controller:discount,keyboardType:TextInputType.number,inputFormatters:discountType=='amount'?[ThousandsSeparatorInputFormatter()]:[],decoration:InputDecoration(labelText:discountType=='amount'?'تخفیف (تومان)':'تخفیف (درصد)')))
        ]),
        const SizedBox(height:12),_field(seller,'نام فروشنده / مجموعه'),const SizedBox(height:8),Row(children:[Expanded(child:_field(p1,'شماره تماس ۱')),const SizedBox(width:8),Expanded(child:_field(p2,'شماره تماس ۲'))]),const SizedBox(height:8),
        _field(card,'شماره کارت'),const SizedBox(height:8),_field(shaba,'شماره شبا'),const SizedBox(height:8),_field(notes,'توضیحات',lines:2)
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('ذخیره'))]
    )));
    if(ok!=true)return;final dv=double.tryParse(discount.text.replaceAll(',',''))??0;
    final inv=invoice??InvoiceRecord(id:newId(),date:'',title:'',items:[],documentType:type);
    inv..date=date.text.trim()..internalName=internalName.text.trim()..title=title.text.trim()..documentNumber=number.text.trim()..validUntil=validUntil.text.trim()..notes=notes.text.trim()
      ..sellerName=seller.text.trim()..sellerPhone1=p1.text.trim()..sellerPhone2=p2.text.trim()..cardNumber=card.text.trim()..shaba=shaba.text.trim()
      ..discountType=discountType..discountValue=dv..status=status..items=items.where((e)=>e.description.trim().isNotEmpty||e.unitPrice!=0).toList();
    if(invoice==null)c.invoices.insert(0,inv);await _save();
  }

  Future<void> _convertProforma(InvoiceRecord p) async {
    if(!p.isProforma||p.status=='converted')return;
    final yes=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:const Text('تبدیل پیش‌فاکتور به فاکتور'),content:const Text('یک فاکتور جدید با همین ردیف‌ها و مبالغ ساخته می‌شود و پیش‌فاکتور در سوابق باقی می‌ماند.'),actions:[
      TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('تبدیل به فاکتور'))
    ]));
    if(yes!=true)return;
    final inv=InvoiceRecord(id:newId(),date:today(),title:'فاکتور خدمات',internalName:p.internalName.trim().isEmpty?p.title:p.internalName,documentType:'invoice',documentNumber:_nextDocumentNumber('invoice'),
      items:p.items.map((e)=>InvoiceItem(description:e.description,quantity:e.quantity,unitPrice:e.unitPrice)).toList(),notes:p.notes,sellerName:p.sellerName,sellerPhone1:p.sellerPhone1,sellerPhone2:p.sellerPhone2,cardNumber:p.cardNumber,shaba:p.shaba,discountType:p.discountType,discountValue:p.discountValue,status:'open');
    c.invoices.insert(0,inv);p.status='converted';p.convertedToInvoiceId=inv.id;await _save();
  }

  Future<void> _pdf(InvoiceRecord i) async {
    final font=await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');final doc=pw.Document();final f=pw.Font.ttf(font);
    doc.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,margin:const pw.EdgeInsets.all(26),theme:pw.ThemeData.withFont(base:f,bold:f),textDirection:pw.TextDirection.rtl,build:(ctx)=>[
      pw.Container(padding:const pw.EdgeInsets.all(16),decoration:pw.BoxDecoration(color:PdfColors.teal50,border:pw.Border.all(color:PdfColors.teal300),borderRadius:pw.BorderRadius.circular(8)),child:pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[
        pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[pw.Text(i.sellerName.isEmpty?'کارنوپلاس':i.sellerName,style:pw.TextStyle(fontSize:22,fontWeight:pw.FontWeight.bold)),pw.Text([i.sellerPhone1,i.sellerPhone2].where((e)=>e.isNotEmpty).join(' - '))]),
        pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.end,children:[pw.Text(i.typeLabel,style:pw.TextStyle(fontSize:18,fontWeight:pw.FontWeight.bold)),if(i.documentNumber.isNotEmpty)pw.Text('شماره: ${i.documentNumber}'),pw.Text('تاریخ: ${i.date}'),if(i.isProforma&&i.validUntil.isNotEmpty)pw.Text('اعتبار تا: ${i.validUntil}')])
      ])),
      pw.SizedBox(height:14),pw.Container(width:double.infinity,padding:const pw.EdgeInsets.all(12),decoration:pw.BoxDecoration(border:pw.Border.all(color:PdfColors.grey400),borderRadius:pw.BorderRadius.circular(6)),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:[
        pw.Text('مشخصات خریدار',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),pw.Divider(),
        pw.Text('نام: ${c.name}',textAlign:pw.TextAlign.right),
        if(c.phone.isNotEmpty)pw.Text('تلفن: ${c.phone}',textAlign:pw.TextAlign.right),
        if(c.address.isNotEmpty)pw.Text('آدرس: ${c.address}',textAlign:pw.TextAlign.right),
        if(c.devices.isNotEmpty)pw.Text('دستگاه: ${c.devices.map((e)=>e.name).join('، ')}',textAlign:pw.TextAlign.right)
      ])),
      pw.SizedBox(height:14),pw.Text(i.title,style:pw.TextStyle(fontSize:16,fontWeight:pw.FontWeight.bold)),pw.SizedBox(height:8),
      pw.TableHelper.fromTextArray(headers:['مبلغ','فی واحد','تعداد','شرح','ردیف'],data:i.items.asMap().entries.map((e)=>[money(e.value.amount),money(e.value.unitPrice),e.value.quantity.toStringAsFixed(e.value.quantity%1==0?0:1),e.value.description,'${e.key+1}']).toList(),
        columnWidths:{0:const pw.FlexColumnWidth(1.5),1:const pw.FlexColumnWidth(1.4),2:const pw.FlexColumnWidth(.8),3:const pw.FlexColumnWidth(3.1),4:const pw.FlexColumnWidth(.6)},headerDecoration:const pw.BoxDecoration(color:PdfColors.teal50),headerStyle:pw.TextStyle(fontWeight:pw.FontWeight.bold),border:pw.TableBorder.all(color:PdfColors.grey400),cellAlignments:{0:pw.Alignment.centerLeft,1:pw.Alignment.centerLeft,2:pw.Alignment.center,3:pw.Alignment.centerRight,4:pw.Alignment.center},cellPadding:const pw.EdgeInsets.all(7)),
      pw.SizedBox(height:12),pw.Align(alignment:pw.Alignment.centerLeft,child:pw.Container(width:250,padding:const pw.EdgeInsets.all(10),decoration:pw.BoxDecoration(border:pw.Border.all(color:PdfColors.grey400),borderRadius:pw.BorderRadius.circular(5)),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:[
        pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Text('جمع جزء'),pw.Text(money(i.subtotal))]),
        if(i.discountAmount>0)pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Text('تخفیف${i.discountType=='percent'?' (${i.discountValue.toStringAsFixed(0)}٪)':''}'),pw.Text(money(i.discountAmount))]),
        pw.Divider(),pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Text('مبلغ نهایی',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),pw.Text(money(i.total),style:pw.TextStyle(fontWeight:pw.FontWeight.bold))])
      ]))),
      pw.SizedBox(height:14),if(i.cardNumber.isNotEmpty||i.shaba.isNotEmpty)pw.Container(padding:const pw.EdgeInsets.all(10),decoration:pw.BoxDecoration(color:PdfColors.grey100,borderRadius:pw.BorderRadius.circular(5)),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:[if(i.cardNumber.isNotEmpty)pw.Text('شماره کارت: ${i.cardNumber}'),if(i.shaba.isNotEmpty)pw.Text('شماره شبا: ${i.shaba}')])),
      if(i.notes.isNotEmpty)...[pw.SizedBox(height:12),pw.Container(padding:const pw.EdgeInsets.all(10),decoration:pw.BoxDecoration(border:pw.Border.all(color:PdfColors.grey400),borderRadius:pw.BorderRadius.circular(5)),child:pw.Text('توضیحات: ${i.notes}'))],
      pw.SizedBox(height:24),pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Column(children:[pw.Text('مهر و امضای فروشنده'),pw.SizedBox(height:32)]),pw.Column(children:[pw.Text('امضای مشتری'),pw.SizedBox(height:32)])]),
      pw.Divider(color:PdfColors.grey400),pw.Text(i.isProforma?'این سند پیش‌فاکتور است و تا تاریخ درج‌شده معتبر است.':'وضعیت: ${i.statusLabel}',style:const pw.TextStyle(fontSize:9,color:PdfColors.grey700))
    ]));
    final Uint8List bytes=await doc.save();final rawName=i.internalName.trim().isEmpty?'${i.isProforma?'پیش‌فاکتور':'فاکتور'}-${i.documentNumber.isEmpty?i.id:i.documentNumber}':i.internalName.trim();final safeName=rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'),' ').replaceAll(RegExp(r'\s+'),' ').trim();await Printing.sharePdf(bytes:bytes,filename:'${safeName.isEmpty?'document':safeName}.pdf');
  }

  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(c.name),actions:[IconButton(onPressed:()async{await widget.onEditCustomer();if(mounted)setState((){});},icon:const Icon(Icons.edit_outlined))]),body:ListView(padding:const EdgeInsets.all(16),children:[
    _infoCard(),const SizedBox(height:12),Row(children:[Expanded(child:FilledButton.icon(onPressed:()=>_serviceForm(),icon:const Icon(Icons.build_outlined),label:const Text('ثبت سرویس'))),const SizedBox(width:8),Expanded(child:FilledButton.tonalIcon(onPressed:()=>_paymentForm(),icon:const Icon(Icons.payments_outlined),label:const Text('ثبت پرداخت')))]),const SizedBox(height:8),Row(children:[Expanded(child:FilledButton.tonalIcon(onPressed:()=>_invoiceForm(documentType:'invoice'),icon:const Icon(Icons.receipt_long_outlined),label:const Text('فاکتور جدید'))),const SizedBox(width:8),Expanded(child:FilledButton.tonalIcon(onPressed:()=>_invoiceForm(documentType:'proforma'),icon:const Icon(Icons.request_quote_outlined),label:const Text('پیش‌فاکتور')))]),const SizedBox(height:8),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:_reportDialog,icon:const Icon(Icons.analytics_outlined),label:const Text('گزارش عملکرد'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:()=>_deviceForm(),icon:const Icon(Icons.add_circle_outline),label:const Text('افزودن دستگاه')))]),const SizedBox(height:20),
    _section('دستگاه‌های مشتری',c.devices.map((d)=>ListTile(title:Text(d.name),subtitle:Text(d.nextServiceDate.isEmpty?d.notes:'سرویس بعدی: ${d.nextServiceDate}\n${d.notes}'),trailing:Wrap(spacing:0,children:[IconButton(onPressed:()=>_deviceSmsEditor(d),icon:const Icon(Icons.sms_outlined)),IconButton(onPressed:()=>_deviceForm(device:d),icon:const Icon(Icons.edit_outlined))]))).toList()),
    _section('فاکتورها و پیش‌فاکتورها',c.invoices.map((i)=>ListTile(title:Text(i.internalName.trim().isEmpty?'${i.typeLabel} ${i.documentNumber}':i.internalName,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text('${i.typeLabel}${i.documentNumber.isEmpty?'':' • ${i.documentNumber}'}\n${i.date} • ${money(i.total)} • ${i.statusLabel}'),isThreeLine:true,trailing:Wrap(spacing:0,children:[if(i.isProforma&&i.status!='converted')IconButton(onPressed:()=>_convertProforma(i),icon:const Icon(Icons.transform_outlined),tooltip:'تبدیل به فاکتور'),IconButton(onPressed:()=>_pdf(i),icon:const Icon(Icons.picture_as_pdf_outlined),tooltip:'PDF'),IconButton(onPressed:()=>_invoiceForm(invoice:i),icon:const Icon(Icons.edit_outlined),tooltip:'ویرایش')]))).toList()),
    _section('سابقه خدمات',c.services.map((r)=>ListTile(title:Text(r.description),subtitle:Text('${_deviceById(r.deviceId)?.name ?? (c.devices.isNotEmpty?c.devices.first.name:'')} • ${r.date} • ${money(r.amount)}${r.nextDate.isEmpty?'':'\nسرویس بعدی: ${r.nextDate}'}'),trailing:IconButton(onPressed:()=>_serviceForm(record:r),icon:const Icon(Icons.edit_outlined)))).toList()),
    _section('پرداخت‌ها',c.payments.map((r)=>ListTile(title:Text(money(r.amount)),subtitle:Text('${r.date}${r.note.isEmpty?'':' • ${r.note}'}'),trailing:IconButton(onPressed:()=>_paymentForm(record:r),icon:const Icon(Icons.edit_outlined)))).toList()),
  ]));

  Widget _infoCard()=>Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20)),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text(c.name,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800)),const SizedBox(height:8),if(c.phone.isNotEmpty)Text('تلفن: ${c.phone}'),if(c.address.isNotEmpty)Text('آدرس: ${c.address}'),Text('تعداد دستگاه‌ها: ${c.devices.length}'),const Divider(height:24),Text('مانده فاکتورها: ${money(c.balance)}',style:TextStyle(fontWeight:FontWeight.bold,color:c.balance>0?Colors.red.shade700:Colors.green.shade700))]));
  Widget _section(String title,List<Widget> rows)=>Padding(padding:const EdgeInsets.only(bottom:16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text(title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800)),const SizedBox(height:8),Container(decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(16)),child:rows.isEmpty?const Padding(padding:EdgeInsets.all(16),child:Text('موردی ثبت نشده')):Column(children:rows))]));
}

class SettingsScreen extends StatefulWidget{
  const SettingsScreen({super.key,required this.settings,required this.templates,required this.onSave});final AppSettings settings;final List<SmsTemplate> templates;final Future<void> Function() onSave;
  @override State<SettingsScreen> createState()=>_SettingsScreenState();
}
class _SettingsScreenState extends State<SettingsScreen>{
  late TextEditingController seller,p1,p2,card,shaba,completionSms;late int hour,minute;late bool autoBackup;
  @override void initState(){super.initState();seller=TextEditingController(text:widget.settings.sellerName);p1=TextEditingController(text:widget.settings.sellerPhone1);p2=TextEditingController(text:widget.settings.sellerPhone2);card=TextEditingController(text:widget.settings.cardNumber);shaba=TextEditingController(text:widget.settings.shaba);completionSms=TextEditingController(text:widget.settings.completionSmsTemplate);hour=widget.settings.smsHour;minute=widget.settings.smsMinute;autoBackup=widget.settings.autoBackup;}
  Future<void> _templateEdit(SmsTemplate t)async{final title=TextEditingController(text:t.title),body=TextEditingController(text:t.body);final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:const Text('ویرایش قالب پیامک'),content:Column(mainAxisSize:MainAxisSize.min,children:[_field(title,'نام قالب'),const SizedBox(height:8),_field(body,'متن پیامک',lines:6,hint:'{نام} {دستگاه} {تاریخ}')]),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('ذخیره'))]));if(ok==true){t..title=title.text.trim()..body=body.text.trim();await widget.onSave();if(mounted)setState((){});}}
  Future<void> _enableSms()async{final ok=await Permission.sms.request();if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(ok.isGranted?'مجوز پیامک فعال شد':'مجوز پیامک داده نشد')));}
  Future<void> _save()async{widget.settings..sellerName=seller.text.trim()..sellerPhone1=p1.text.trim()..sellerPhone2=p2.text.trim()..cardNumber=card.text.trim()..shaba=shaba.text.trim()..completionSmsTemplate=completionSms.text.trim()..smsHour=hour..smsMinute=minute..autoBackup=autoBackup;await widget.onSave();if(mounted)Navigator.pop(context);}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('تنظیمات')),body:ListView(padding:const EdgeInsets.all(16),children:[const Text('اطلاعات پیش‌فرض فاکتور',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:10),_field(seller,'نام مجموعه'),const SizedBox(height:8),_field(p1,'شماره تماس ۱'),const SizedBox(height:8),_field(p2,'شماره تماس ۲'),const SizedBox(height:8),_field(card,'شماره کارت'),const SizedBox(height:8),_field(shaba,'شماره شبا'),const SizedBox(height:20),
    const Text('پیامک پایان کار',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),_field(completionSms,'متن پیام پایان کار',lines:5,hint:'متغیرها: {نام} {دستگاه} {شرح} {تاریخ}'),const SizedBox(height:20),
    const Text('پیامک یادآوری',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),Row(children:[Expanded(child:DropdownButtonFormField<int>(value:hour,decoration:const InputDecoration(labelText:'ساعت'),items:List.generate(24,(i)=>DropdownMenuItem(value:i,child:Text(i.toString().padLeft(2,'0')))),onChanged:(v)=>setState(()=>hour=v??9))),const SizedBox(width:8),Expanded(child:DropdownButtonFormField<int>(value:minute,decoration:const InputDecoration(labelText:'دقیقه'),items:[0,15,30,45].map((i)=>DropdownMenuItem(value:i,child:Text(i.toString().padLeft(2,'0')))).toList(),onChanged:(v)=>setState(()=>minute=v??0)))]),const SizedBox(height:8),OutlinedButton.icon(onPressed:_enableSms,icon:const Icon(Icons.sms),label:const Text('فعال‌سازی مجوز پیامک')),const SizedBox(height:8),...widget.templates.map((t)=>Card(child:ListTile(title:Text(t.title),subtitle:Text(t.body,maxLines:2,overflow:TextOverflow.ellipsis),trailing:IconButton(onPressed:()=>_templateEdit(t),icon:const Icon(Icons.edit_outlined))))),const SizedBox(height:16),SwitchListTile(value:autoBackup,onChanged:(v)=>setState(()=>autoBackup=v),title:const Text('بکاپ خودکار روزانه'),subtitle:const Text('روزی یک‌بار هنگام باز شدن برنامه در Downloads ذخیره می‌شود')),const SizedBox(height:16),FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save_outlined),label:const Text('ذخیره تنظیمات'))]));
}

Widget _field(TextEditingController c,String label,{int lines=1,TextInputType? type,String? hint})=>TextField(controller:c,maxLines:lines,keyboardType:type,decoration:InputDecoration(labelText:label,hintText:hint));
