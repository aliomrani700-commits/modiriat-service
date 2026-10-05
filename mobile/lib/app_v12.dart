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
  });
  String sellerName, sellerPhone1, sellerPhone2, cardNumber, shaba;
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
      );
}

class SmsTemplate {
  SmsTemplate({required this.id, required this.title, required this.body});
  String id, title, body;
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'body': body};
  factory SmsTemplate.fromJson(Map<String, dynamic> j) => SmsTemplate(id: j['id']?.toString() ?? '', title: j['title']?.toString() ?? '', body: j['body']?.toString() ?? '');
}

class ServiceRecord {
  ServiceRecord({required this.id, required this.date, required this.description, required this.amount, this.nextDate = ''});
  String id, date, description, nextDate;
  double amount;
  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'description': description, 'amount': amount, 'nextDate': nextDate};
  factory ServiceRecord.fromJson(Map<String, dynamic> j) => ServiceRecord(
        id: j['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
        date: j['date']?.toString() ?? '', description: j['description']?.toString() ?? '', amount: (j['amount'] as num?)?.toDouble() ?? 0, nextDate: j['nextDate']?.toString() ?? '');
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
  InvoiceItem({required this.description, required this.amount});
  String description;
  double amount;
  Map<String, dynamic> toJson() => {'description': description, 'amount': amount};
  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(description: j['description']?.toString() ?? '', amount: (j['amount'] as num?)?.toDouble() ?? 0);
}

class InvoiceRecord {
  InvoiceRecord({
    required this.id, required this.date, required this.title, required this.items,
    this.notes = '', this.sellerName = '', this.sellerPhone1 = '', this.sellerPhone2 = '', this.cardNumber = '', this.shaba = '',
  });
  String id, date, title, notes, sellerName, sellerPhone1, sellerPhone2, cardNumber, shaba;
  List<InvoiceItem> items;
  double get total => items.fold(0, (s, e) => s + e.amount);
  Map<String, dynamic> toJson() => {
        'id': id, 'date': date, 'title': title, 'notes': notes, 'sellerName': sellerName, 'sellerPhone1': sellerPhone1,
        'sellerPhone2': sellerPhone2, 'cardNumber': cardNumber, 'shaba': shaba, 'items': items.map((e) => e.toJson()).toList(),
      };
  factory InvoiceRecord.fromJson(Map<String, dynamic> j) => InvoiceRecord(
        id: j['id']?.toString() ?? '', date: j['date']?.toString() ?? '', title: j['title']?.toString() ?? 'فاکتور', notes: j['notes']?.toString() ?? '',
        sellerName: j['sellerName']?.toString() ?? '', sellerPhone1: j['sellerPhone1']?.toString() ?? '', sellerPhone2: j['sellerPhone2']?.toString() ?? '',
        cardNumber: j['cardNumber']?.toString() ?? '', shaba: j['shaba']?.toString() ?? '',
        items: ((j['items'] as List?) ?? []).map((e) => InvoiceItem.fromJson(Map<String, dynamic>.from(e))).toList());
}

class Customer {
  Customer({required this.id, required this.name, this.phone = '', this.address = '', this.deviceType = '', this.notes = '', this.nextServiceDate = '', this.smsTemplateId = '', this.customSms = '', List<ServiceRecord>? services, List<PaymentRecord>? payments, List<InvoiceRecord>? invoices})
      : services = services ?? [], payments = payments ?? [], invoices = invoices ?? [];
  String id, name, phone, address, deviceType, notes, nextServiceDate, smsTemplateId, customSms;
  List<ServiceRecord> services;
  List<PaymentRecord> payments;
  List<InvoiceRecord> invoices;
  double get totalServices => services.fold(0, (s, e) => s + e.amount);
  double get totalPayments => payments.fold(0, (s, e) => s + e.amount);
  double get balance => totalServices - totalPayments;
  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'phone': phone, 'address': address, 'deviceType': deviceType, 'vehicle': deviceType, 'notes': notes,
        'nextServiceDate': nextServiceDate, 'smsTemplateId': smsTemplateId, 'customSms': customSms,
        'services': services.map((e) => e.toJson()).toList(), 'payments': payments.map((e) => e.toJson()).toList(), 'invoices': invoices.map((e) => e.toJson()).toList(),
      };
  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id']?.toString() ?? '', name: j['name']?.toString() ?? '', phone: j['phone']?.toString() ?? '', address: j['address']?.toString() ?? '',
        deviceType: (j['deviceType'] ?? j['vehicle'])?.toString() ?? '', notes: j['notes']?.toString() ?? '', nextServiceDate: j['nextServiceDate']?.toString() ?? '',
        smsTemplateId: j['smsTemplateId']?.toString() ?? '', customSms: j['customSms']?.toString() ?? '',
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
    if (templates.isEmpty) templates.addAll(defaultSmsTemplates());
    for (final c in customers) { if (c.smsTemplateId.isEmpty) c.smsTemplateId = templates.first.id; }
    await _saveCore(dailyBackup: true);
    await _scheduleAll();
    if (mounted) setState(() => loading = false);
  }

  Map<String,dynamic> _fullBackup() => {'version': 2, 'createdAt': DateTime.now().toIso8601String(), 'customers': customers.map((e)=>e.toJson()).toList(), 'templates': templates.map((e)=>e.toJson()).toList(), 'settings': settings.toJson()};

  Future<void> _saveCore({bool dailyBackup = true}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_storageKey, jsonEncode(customers.map((e)=>e.toJson()).toList()));
    await p.setString(_templatesKey, jsonEncode(templates.map((e)=>e.toJson()).toList()));
    await p.setString(_settingsKey, jsonEncode(settings.toJson()));
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

  SmsTemplate templateFor(Customer c) => templates.firstWhere((e)=>e.id==c.smsTemplateId, orElse: ()=>templates.first);
  String smsFor(Customer c) => renderSms(c.customSms.trim().isNotEmpty ? c.customSms : templateFor(c).body, c);

  Future<void> _schedule(Customer c) async {
    if (c.phone.trim().isEmpty || c.nextServiceDate.trim().isEmpty) return;
    final when = parseServiceDate(c.nextServiceDate, settings); if (when == null || when.isBefore(DateTime.now())) return;
    if (!(await Permission.sms.status).isGranted) return;
    try { await _channel.invokeMethod('scheduleSms', {'id': c.id.hashCode & 0x7fffffff, 'phone': c.phone.trim(), 'message': smsFor(c), 'timeMillis': when.millisecondsSinceEpoch}); } catch (_) {}
  }
  Future<void> _scheduleAll() async { for (final c in customers) { await _schedule(c); } }

  List<Customer> get filtered {
    final q=search.text.trim().toLowerCase(); if(q.isEmpty)return customers;
    return customers.where((c)=>[c.name,c.phone,c.deviceType,c.address].any((x)=>x.toLowerCase().contains(q))).toList();
  }

  Future<void> _customerForm({Customer? customer}) async {
    final name=TextEditingController(text:customer?.name??''), phone=TextEditingController(text:customer?.phone??''), address=TextEditingController(text:customer?.address??''), device=TextEditingController(text:customer?.deviceType??''), next=TextEditingController(text:customer?.nextServiceDate??''), notes=TextEditingController(text:customer?.notes??'');
    var tpl=customer?.smsTemplateId.isNotEmpty==true?customer!.smsTemplateId:templates.first.id;
    final ok=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:Text(customer==null?'مشتری جدید':'ویرایش مشتری'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      _field(name,'نام مشتری'),const SizedBox(height:8),_field(phone,'شماره تماس',type:TextInputType.phone),const SizedBox(height:8),_field(address,'آدرس',lines:2),const SizedBox(height:8),_field(device,'نوع دستگاه'),const SizedBox(height:8),_field(next,'تاریخ سرویس بعدی',hint:'مثلاً 1405/08/20'),const SizedBox(height:8),
      DropdownButtonFormField<String>(value:tpl,decoration:const InputDecoration(labelText:'قالب پیامک'),items:templates.map((e)=>DropdownMenuItem(value:e.id,child:Text(e.title))).toList(),onChanged:(v){if(v!=null)setD(()=>tpl=v);}),const SizedBox(height:8),_field(notes,'توضیحات',lines:2)
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('ذخیره'))]))));
    if(ok!=true||name.text.trim().isEmpty)return;
    final c=customer??Customer(id:newId(),name:name.text.trim());
    c..name=name.text.trim()..phone=phone.text.trim()..address=address.text.trim()..deviceType=device.text.trim()..nextServiceDate=next.text.trim()..notes=notes.text.trim()..smsTemplateId=tpl;
    if(customer==null)customers.insert(0,c);
    await _saveCore(); await _schedule(c);
  }

  Future<void> _backupDialog() async {
    await showDialog(context:context,builder:(d)=>AlertDialog(title:const Text('بکاپ و بازیابی'),content:const Text('بکاپ دستی در پوشه Download/ModiriatService ذخیره می‌شود. بکاپ خودکار نیز روزی یک‌بار هنگام باز شدن برنامه انجام می‌شود.'),actions:[
      TextButton(onPressed:()async{await Clipboard.setData(ClipboardData(text:jsonEncode(_fullBackup())));if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('بکاپ در کلیپ‌بورد کپی شد')));},child:const Text('کپی بکاپ')),
      TextButton(onPressed:()async{try{final ok=await _channel.invokeMethod<bool>('saveBackup',{'json':jsonEncode(_fullBackup()),'fileName':'modiriat-service-manual-${DateTime.now().millisecondsSinceEpoch}.json'});if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(ok==true?'بکاپ در Downloads ذخیره شد':'ذخیره بکاپ انجام نشد')));}catch(_){ }},child:const Text('ذخیره در Downloads')),
      FilledButton(onPressed:()async{final clip=await Clipboard.getData('text/plain');try{final j=jsonDecode(clip?.text??'');final map=Map<String,dynamic>.from(j);customers..clear()..addAll((map['customers'] as List).map((e)=>Customer.fromJson(Map<String,dynamic>.from(e))));if(map['templates'] is List){templates..clear()..addAll((map['templates'] as List).map((e)=>SmsTemplate.fromJson(Map<String,dynamic>.from(e))));}if(map['settings'] is Map)settings=AppSettings.fromJson(Map<String,dynamic>.from(map['settings']));await _saveCore();await _scheduleAll();if(d.mounted)Navigator.pop(d);}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('بکاپ معتبر نیست')));}},child:const Text('بازیابی از کلیپ‌بورد'))
    ]));
  }

  Future<void> _settings() async { await Navigator.push(context,MaterialPageRoute(builder:(_)=>SettingsScreen(settings:settings,templates:templates,onSave:()async{await _saveCore();await _scheduleAll();}))); if(mounted)setState((){}); }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('کارنوپلاس | مدیریت سرویس',style:TextStyle(fontWeight:FontWeight.w800)),actions:[IconButton(onPressed:_backupDialog,icon:const Icon(Icons.backup_outlined),tooltip:'بکاپ'),IconButton(onPressed:_settings,icon:const Icon(Icons.settings_outlined),tooltip:'تنظیمات')]),
    floatingActionButton:FloatingActionButton.extended(onPressed:()=>_customerForm(),icon:const Icon(Icons.person_add_alt_1),label:const Text('مشتری جدید')),
    body:loading?const Center(child:CircularProgressIndicator()):Column(children:[
      Container(margin:const EdgeInsets.fromLTRB(16,8,16,12),padding:const EdgeInsets.all(16),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF0F766E),Color(0xFF115E59)]),borderRadius:BorderRadius.circular(22)),child:Row(children:[Expanded(child:_stat('مشتری',customers.length.toString())),Expanded(child:_stat('طلب کل',money(customers.fold(0.0,(s,c)=>s+(c.balance>0?c.balance:0)))))])),
      Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:TextField(controller:search,onChanged:(_)=>setState((){}),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'جستجو نام، شماره، دستگاه یا آدرس...'))),const SizedBox(height:10),
      Expanded(child:filtered.isEmpty?const Center(child:Text('هنوز مشتری ثبت نشده')):ListView.separated(padding:const EdgeInsets.fromLTRB(16,0,16,100),itemCount:filtered.length,separatorBuilder:(_,__)=>const SizedBox(height:10),itemBuilder:(ctx,i){final c=filtered[i];return Card(child:ListTile(contentPadding:const EdgeInsets.all(14),leading:CircleAvatar(child:Text(c.name.isEmpty?'?':c.name.substring(0,1))),title:Text(c.name,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text([if(c.deviceType.isNotEmpty)c.deviceType,if(c.phone.isNotEmpty)c.phone,if(c.nextServiceDate.isNotEmpty)'سرویس بعدی: ${c.nextServiceDate}', 'مانده: ${money(c.balance)}'].join('\n')),trailing:const Icon(Icons.chevron_left),onTap:()async{await Navigator.push(context,MaterialPageRoute(builder:(_)=>CustomerScreen(customer:c,templates:templates,settings:settings,onSave:_saveCore,onSchedule:_schedule,onEditCustomer:()=>_customerForm(customer:c))));if(mounted)setState((){});}));}))
    ]));

  Widget _stat(String a,String b)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(a,style:const TextStyle(color:Colors.white70)),const SizedBox(height:4),Text(b,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold,fontSize:18))]);
}

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key,required this.customer,required this.templates,required this.settings,required this.onSave,required this.onSchedule,required this.onEditCustomer});
  final Customer customer; final List<SmsTemplate> templates; final AppSettings settings; final Future<void> Function({bool dailyBackup}) onSave; final Future<void> Function(Customer) onSchedule; final Future<void> Function() onEditCustomer;
  @override State<CustomerScreen> createState()=>_CustomerScreenState();
}
class _CustomerScreenState extends State<CustomerScreen>{
  Customer get c=>widget.customer;
  Future<void> _save()async{await widget.onSave();if(mounted)setState((){});}

  Future<void> _smsEditor() async {
    final tpl=widget.templates.firstWhere((e)=>e.id==c.smsTemplateId,orElse:()=>widget.templates.first);
    final ctrl=TextEditingController(text:c.customSms.isNotEmpty?c.customSms:tpl.body);
    final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:const Text('متن پیامک یادآوری'),content:Column(mainAxisSize:MainAxisSize.min,children:[Text('پیش‌نمایش: ${renderSms(ctrl.text,c)}'),const SizedBox(height:10),TextField(controller:ctrl,maxLines:6,decoration:const InputDecoration(labelText:'متن پیامک',helperText:'متغیرها: {نام}  {دستگاه}  {تاریخ}'))]),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('ذخیره و زمان‌بندی'))]));
    if(ok==true){c.customSms=ctrl.text.trim();await _save();await widget.onSchedule(c);}
  }

  Future<void> _serviceForm({ServiceRecord? record}) async {
    final desc=TextEditingController(text:record?.description??''), amount=TextEditingController(text:record==null?'':record.amount.toStringAsFixed(0)), date=TextEditingController(text:record?.date??today()), next=TextEditingController(text:record?.nextDate??c.nextServiceDate);
    final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:Text(record==null?'ثبت سرویس':'ویرایش سرویس'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[_field(desc,'شرح سرویس'),const SizedBox(height:8),_field(amount,'مبلغ (تومان)',type:TextInputType.number),const SizedBox(height:8),_field(date,'تاریخ'),const SizedBox(height:8),_field(next,'سرویس بعدی')])),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('ذخیره'))]));
    if(ok!=true||desc.text.trim().isEmpty)return;final r=record??ServiceRecord(id:newId(),date:'',description:'',amount:0);r..description=desc.text.trim()..amount=double.tryParse(amount.text.replaceAll(',',''))??0..date=date.text.trim()..nextDate=next.text.trim();if(record==null)c.services.insert(0,r);if(next.text.trim().isNotEmpty)c.nextServiceDate=next.text.trim();await _save();await widget.onSchedule(c);
  }

  Future<void> _paymentForm({PaymentRecord? record}) async {
    final amount=TextEditingController(text:record==null?'':record.amount.toStringAsFixed(0)),date=TextEditingController(text:record?.date??today()),note=TextEditingController(text:record?.note??'');
    final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:Text(record==null?'ثبت پرداخت':'ویرایش پرداخت'),content:Column(mainAxisSize:MainAxisSize.min,children:[_field(amount,'مبلغ (تومان)',type:TextInputType.number),const SizedBox(height:8),_field(date,'تاریخ'),const SizedBox(height:8),_field(note,'توضیحات')]),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('ذخیره'))]));
    if(ok!=true)return;final r=record??PaymentRecord(id:newId(),date:'',amount:0);r..amount=double.tryParse(amount.text.replaceAll(',',''))??0..date=date.text.trim()..note=note.text.trim();if(record==null)c.payments.insert(0,r);await _save();
  }

  Future<void> _invoiceForm({InvoiceRecord? invoice}) async {
    final date=TextEditingController(text:invoice?.date??today()),title=TextEditingController(text:invoice?.title??'فاکتور خدمات'),notes=TextEditingController(text:invoice?.notes??''),seller=TextEditingController(text:invoice?.sellerName.isNotEmpty==true?invoice!.sellerName:widget.settings.sellerName),p1=TextEditingController(text:invoice?.sellerPhone1.isNotEmpty==true?invoice!.sellerPhone1:widget.settings.sellerPhone1),p2=TextEditingController(text:invoice?.sellerPhone2.isNotEmpty==true?invoice!.sellerPhone2:widget.settings.sellerPhone2),card=TextEditingController(text:invoice?.cardNumber.isNotEmpty==true?invoice!.cardNumber:widget.settings.cardNumber),shaba=TextEditingController(text:invoice?.shaba.isNotEmpty==true?invoice!.shaba:widget.settings.shaba);
    final items=(invoice?.items.map((e)=>InvoiceItem(description:e.description,amount:e.amount)).toList()??[InvoiceItem(description:'',amount:0)]);
    final ok=await showDialog<bool>(context:context,builder:(d)=>StatefulBuilder(builder:(d,setD)=>AlertDialog(title:Text(invoice==null?'فاکتور جدید':'ویرایش فاکتور'),content:SizedBox(width:500,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[_field(title,'عنوان فاکتور'),const SizedBox(height:8),_field(date,'تاریخ'),const SizedBox(height:8),_field(seller,'نام فروشنده / مجموعه'),const SizedBox(height:8),_field(p1,'شماره تماس ۱'),const SizedBox(height:8),_field(p2,'شماره تماس ۲'),const SizedBox(height:8),_field(card,'شماره کارت'),const SizedBox(height:8),_field(shaba,'شماره شبا'),const Divider(height:28),...items.asMap().entries.map((e){final dc=TextEditingController(text:e.value.description),ac=TextEditingController(text:e.value.amount==0?'':e.value.amount.toStringAsFixed(0));return Padding(padding:const EdgeInsets.only(bottom:8),child:Row(children:[Expanded(flex:2,child:TextField(controller:dc,decoration:const InputDecoration(labelText:'شرح'),onChanged:(v)=>e.value.description=v)),const SizedBox(width:6),Expanded(child:TextField(controller:ac,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'مبلغ'),onChanged:(v)=>e.value.amount=double.tryParse(v.replaceAll(',',''))??0)),IconButton(onPressed:items.length==1?null:()=>setD(()=>items.removeAt(e.key)),icon:const Icon(Icons.delete_outline))]));}),Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:()=>setD(()=>items.add(InvoiceItem(description:'',amount:0))),icon:const Icon(Icons.add),label:const Text('ردیف جدید'))),_field(notes,'توضیحات',lines:2)]))),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('ذخیره'))]))));
    if(ok!=true)return;final inv=invoice??InvoiceRecord(id:newId(),date:'',title:'',items:[]);inv..date=date.text.trim()..title=title.text.trim()..notes=notes.text.trim()..sellerName=seller.text.trim()..sellerPhone1=p1.text.trim()..sellerPhone2=p2.text.trim()..cardNumber=card.text.trim()..shaba=shaba.text.trim()..items=items.where((e)=>e.description.trim().isNotEmpty||e.amount!=0).toList();if(invoice==null)c.invoices.insert(0,inv);await _save();
  }

  Future<void> _pdf(InvoiceRecord i) async {
    final font=await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');final doc=pw.Document();final f=pw.Font.ttf(font);
    doc.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,theme:pw.ThemeData.withFont(base:f,bold:f),textDirection:pw.TextDirection.rtl,build:(ctx)=>[
      pw.Container(padding:const pw.EdgeInsets.all(16),decoration:pw.BoxDecoration(color:PdfColors.teal50,borderRadius:pw.BorderRadius.circular(8)),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:[pw.Text(i.sellerName.isEmpty?'کارنوپلاس':i.sellerName,style:pw.TextStyle(fontSize:22,fontWeight:pw.FontWeight.bold)),pw.Text([i.sellerPhone1,i.sellerPhone2].where((e)=>e.isNotEmpty).join(' - '))])),pw.SizedBox(height:18),
      pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Text(i.title,style:pw.TextStyle(fontSize:18,fontWeight:pw.FontWeight.bold)),pw.Text('تاریخ: ${i.date}')]),pw.SizedBox(height:10),pw.Text('مشتری: ${c.name}'),if(c.phone.isNotEmpty)pw.Text('تماس: ${c.phone}'),if(c.address.isNotEmpty)pw.Text('آدرس: ${c.address}'),if(c.deviceType.isNotEmpty)pw.Text('نوع دستگاه: ${c.deviceType}'),pw.SizedBox(height:14),
      pw.TableHelper.fromTextArray(headers:['شرح','مبلغ'],data:i.items.map((e)=>[e.description,money(e.amount)]).toList(),headerStyle:pw.TextStyle(fontWeight:pw.FontWeight.bold),cellAlignment:pw.Alignment.centerRight),pw.SizedBox(height:12),pw.Align(alignment:pw.Alignment.centerLeft,child:pw.Text('جمع کل: ${money(i.total)}',style:pw.TextStyle(fontSize:16,fontWeight:pw.FontWeight.bold))),if(i.cardNumber.isNotEmpty)...[pw.SizedBox(height:12),pw.Text('شماره کارت: ${i.cardNumber}')],if(i.shaba.isNotEmpty)pw.Text('شماره شبا: ${i.shaba}'),if(i.notes.isNotEmpty)...[pw.SizedBox(height:12),pw.Text('توضیحات: ${i.notes}')]
    ]));
    final Uint8List bytes=await doc.save();await Printing.sharePdf(bytes:bytes,filename:'invoice-${c.name}-${i.date.replaceAll('/','-')}.pdf');
  }

  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(c.name),actions:[IconButton(onPressed:()async{await widget.onEditCustomer();if(mounted)setState((){});},icon:const Icon(Icons.edit_outlined))]),body:ListView(padding:const EdgeInsets.all(16),children:[
    _infoCard(),const SizedBox(height:12),Row(children:[Expanded(child:FilledButton.icon(onPressed:()=>_serviceForm(),icon:const Icon(Icons.build_outlined),label:const Text('ثبت سرویس'))),const SizedBox(width:8),Expanded(child:FilledButton.tonalIcon(onPressed:()=>_paymentForm(),icon:const Icon(Icons.payments_outlined),label:const Text('ثبت پرداخت')))]),const SizedBox(height:8),Row(children:[Expanded(child:FilledButton.tonalIcon(onPressed:()=>_invoiceForm(),icon:const Icon(Icons.receipt_long_outlined),label:const Text('فاکتور جدید'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:_smsEditor,icon:const Icon(Icons.sms_outlined),label:const Text('متن پیامک')))]),const SizedBox(height:20),
    _section('فاکتورهای صادرشده',c.invoices.map((i)=>ListTile(title:Text(i.title),subtitle:Text('${i.date} • ${money(i.total)}'),trailing:Wrap(spacing:0,children:[IconButton(onPressed:()=>_pdf(i),icon:const Icon(Icons.picture_as_pdf_outlined)),IconButton(onPressed:()=>_invoiceForm(invoice:i),icon:const Icon(Icons.edit_outlined))])).toList()),
    _section('سابقه خدمات',c.services.map((r)=>ListTile(title:Text(r.description),subtitle:Text('${r.date} • ${money(r.amount)}${r.nextDate.isEmpty?'':'\nسرویس بعدی: ${r.nextDate}'}'),trailing:IconButton(onPressed:()=>_serviceForm(record:r),icon:const Icon(Icons.edit_outlined)))).toList()),
    _section('پرداخت‌ها',c.payments.map((r)=>ListTile(title:Text(money(r.amount)),subtitle:Text('${r.date}${r.note.isEmpty?'':' • ${r.note}'}'),trailing:IconButton(onPressed:()=>_paymentForm(record:r),icon:const Icon(Icons.edit_outlined)))).toList()),
  ]));

  Widget _infoCard()=>Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(20)),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text(c.name,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800)),const SizedBox(height:8),if(c.phone.isNotEmpty)Text('تلفن: ${c.phone}'),if(c.address.isNotEmpty)Text('آدرس: ${c.address}'),if(c.deviceType.isNotEmpty)Text('نوع دستگاه: ${c.deviceType}'),if(c.nextServiceDate.isNotEmpty)Text('سرویس بعدی: ${c.nextServiceDate} ساعت ${widget.settings.smsHour.toString().padLeft(2,'0')}:${widget.settings.smsMinute.toString().padLeft(2,'0')}'),const Divider(height:24),Text('مانده حساب: ${money(c.balance)}',style:TextStyle(fontWeight:FontWeight.bold,color:c.balance>0?Colors.red.shade700:Colors.green.shade700))]));
  Widget _section(String title,List<Widget> rows)=>Padding(padding:const EdgeInsets.only(bottom:16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text(title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800)),const SizedBox(height:8),Container(decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(16)),child:rows.isEmpty?const Padding(padding:EdgeInsets.all(16),child:Text('موردی ثبت نشده')):Column(children:rows))]));
}

class SettingsScreen extends StatefulWidget{
  const SettingsScreen({super.key,required this.settings,required this.templates,required this.onSave});final AppSettings settings;final List<SmsTemplate> templates;final Future<void> Function() onSave;
  @override State<SettingsScreen> createState()=>_SettingsScreenState();
}
class _SettingsScreenState extends State<SettingsScreen>{
  late TextEditingController seller,p1,p2,card,shaba;late int hour,minute;late bool autoBackup;
  @override void initState(){super.initState();seller=TextEditingController(text:widget.settings.sellerName);p1=TextEditingController(text:widget.settings.sellerPhone1);p2=TextEditingController(text:widget.settings.sellerPhone2);card=TextEditingController(text:widget.settings.cardNumber);shaba=TextEditingController(text:widget.settings.shaba);hour=widget.settings.smsHour;minute=widget.settings.smsMinute;autoBackup=widget.settings.autoBackup;}
  Future<void> _templateEdit(SmsTemplate t)async{final title=TextEditingController(text:t.title),body=TextEditingController(text:t.body);final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:const Text('ویرایش قالب پیامک'),content:Column(mainAxisSize:MainAxisSize.min,children:[_field(title,'نام قالب'),const SizedBox(height:8),_field(body,'متن پیامک',lines:6,hint:'{نام} {دستگاه} {تاریخ}')]),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('ذخیره'))]));if(ok==true){t..title=title.text.trim()..body=body.text.trim();await widget.onSave();if(mounted)setState((){});}}
  Future<void> _enableSms()async{final ok=await Permission.sms.request();if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(ok.isGranted?'مجوز پیامک فعال شد':'مجوز پیامک داده نشد')));}
  Future<void> _save()async{widget.settings..sellerName=seller.text.trim()..sellerPhone1=p1.text.trim()..sellerPhone2=p2.text.trim()..cardNumber=card.text.trim()..shaba=shaba.text.trim()..smsHour=hour..smsMinute=minute..autoBackup=autoBackup;await widget.onSave();if(mounted)Navigator.pop(context);}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('تنظیمات')),body:ListView(padding:const EdgeInsets.all(16),children:[const Text('اطلاعات پیش‌فرض فاکتور',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:10),_field(seller,'نام مجموعه'),const SizedBox(height:8),_field(p1,'شماره تماس ۱'),const SizedBox(height:8),_field(p2,'شماره تماس ۲'),const SizedBox(height:8),_field(card,'شماره کارت'),const SizedBox(height:8),_field(shaba,'شماره شبا'),const SizedBox(height:20),
    const Text('پیامک یادآوری',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:8),Row(children:[Expanded(child:DropdownButtonFormField<int>(value:hour,decoration:const InputDecoration(labelText:'ساعت'),items:List.generate(24,(i)=>DropdownMenuItem(value:i,child:Text(i.toString().padLeft(2,'0')))),onChanged:(v)=>setState(()=>hour=v??9))),const SizedBox(width:8),Expanded(child:DropdownButtonFormField<int>(value:minute,decoration:const InputDecoration(labelText:'دقیقه'),items:[0,15,30,45].map((i)=>DropdownMenuItem(value:i,child:Text(i.toString().padLeft(2,'0')))).toList(),onChanged:(v)=>setState(()=>minute=v??0)))]),const SizedBox(height:8),OutlinedButton.icon(onPressed:_enableSms,icon:const Icon(Icons.sms),label:const Text('فعال‌سازی مجوز پیامک')),const SizedBox(height:8),...widget.templates.map((t)=>Card(child:ListTile(title:Text(t.title),subtitle:Text(t.body,maxLines:2,overflow:TextOverflow.ellipsis),trailing:IconButton(onPressed:()=>_templateEdit(t),icon:const Icon(Icons.edit_outlined))))),const SizedBox(height:16),SwitchListTile(value:autoBackup,onChanged:(v)=>setState(()=>autoBackup=v),title:const Text('بکاپ خودکار روزانه'),subtitle:const Text('روزی یک‌بار هنگام باز شدن برنامه در Downloads ذخیره می‌شود')),const SizedBox(height:16),FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save_outlined),label:const Text('ذخیره تنظیمات'))]));
}

Widget _field(TextEditingController c,String label,{int lines=1,TextInputType? type,String? hint})=>TextField(controller:c,maxLines:lines,keyboardType:type,decoration:InputDecoration(labelText:label,hintText:hint));
