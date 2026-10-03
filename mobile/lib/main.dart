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

void main() => runApp(const ModiriatServiceApp());

class ModiriatServiceApp extends StatelessWidget {
  const ModiriatServiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مدیریت سرویس',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2563EB),
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeScreen(),
    );
  }
}

class InvoiceItem {
  InvoiceItem({required this.description, required this.amount});
  String description;
  double amount;
  Map<String, dynamic> toJson() => {'description': description, 'amount': amount};
  factory InvoiceItem.fromJson(Map<String, dynamic> json) => InvoiceItem(
        description: json['description']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

class InvoiceRecord {
  InvoiceRecord({required this.id, required this.date, required this.title, required this.items, this.notes = ''});
  String id;
  String date;
  String title;
  String notes;
  List<InvoiceItem> items;
  double get total => items.fold(0, (sum, item) => sum + item.amount);
  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'title': title,
        'notes': notes,
        'items': items.map((e) => e.toJson()).toList(),
      };
  factory InvoiceRecord.fromJson(Map<String, dynamic> json) => InvoiceRecord(
        id: json['id']?.toString() ?? '',
        date: json['date']?.toString() ?? '',
        title: json['title']?.toString() ?? 'فاکتور',
        notes: json['notes']?.toString() ?? '',
        items: ((json['items'] as List?) ?? []).map((e) => InvoiceItem.fromJson(Map<String, dynamic>.from(e))).toList(),
      );
}

class SmsTemplate {
  SmsTemplate({required this.id, required this.title, required this.body});
  String id;
  String title;
  String body;
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'body': body};
  factory SmsTemplate.fromJson(Map<String, dynamic> json) => SmsTemplate(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
      );
}

class Customer {
  Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.deviceType = '',
    this.notes = '',
    this.nextServiceDate = '',
    this.smsTemplateId = '',
    List<ServiceRecord>? services,
    List<PaymentRecord>? payments,
    List<InvoiceRecord>? invoices,
  })  : services = services ?? [], payments = payments ?? [], invoices = invoices ?? [];

  String id;
  String name;
  String phone;
  String deviceType;
  String notes;
  String nextServiceDate;
  String smsTemplateId;
  List<ServiceRecord> services;
  List<PaymentRecord> payments;
  List<InvoiceRecord> invoices;
  double get totalServices => services.fold(0, (sum, item) => sum + item.amount);
  double get totalPayments => payments.fold(0, (sum, item) => sum + item.amount);
  double get balance => totalServices - totalPayments;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'deviceType': deviceType,
        'vehicle': deviceType,
        'notes': notes,
        'nextServiceDate': nextServiceDate,
        'smsTemplateId': smsTemplateId,
        'services': services.map((e) => e.toJson()).toList(),
        'payments': payments.map((e) => e.toJson()).toList(),
        'invoices': invoices.map((e) => e.toJson()).toList(),
      };

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        deviceType: (json['deviceType'] ?? json['vehicle'])?.toString() ?? '',
        notes: json['notes']?.toString() ?? '',
        nextServiceDate: json['nextServiceDate']?.toString() ?? '',
        smsTemplateId: json['smsTemplateId']?.toString() ?? '',
        services: ((json['services'] as List?) ?? []).map((e) => ServiceRecord.fromJson(Map<String, dynamic>.from(e))).toList(),
        payments: ((json['payments'] as List?) ?? []).map((e) => PaymentRecord.fromJson(Map<String, dynamic>.from(e))).toList(),
        invoices: ((json['invoices'] as List?) ?? []).map((e) => InvoiceRecord.fromJson(Map<String, dynamic>.from(e))).toList(),
      );
}

class ServiceRecord {
  ServiceRecord({required this.date, required this.description, required this.amount, this.nextDate = ''});
  String date;
  String description;
  double amount;
  String nextDate;
  Map<String, dynamic> toJson() => {'date': date, 'description': description, 'amount': amount, 'nextDate': nextDate};
  factory ServiceRecord.fromJson(Map<String, dynamic> json) => ServiceRecord(
        date: json['date']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        nextDate: json['nextDate']?.toString() ?? '',
      );
}

class PaymentRecord {
  PaymentRecord({required this.date, required this.amount, this.note = ''});
  String date;
  double amount;
  String note;
  Map<String, dynamic> toJson() => {'date': date, 'amount': amount, 'note': note};
  factory PaymentRecord.fromJson(Map<String, dynamic> json) => PaymentRecord(
        date: json['date']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        note: json['note']?.toString() ?? '',
      );
}

class SmsScheduler {
  static const _channel = MethodChannel('modiriat_service/sms');
  static Future<bool> ensurePermission() async => (await Permission.sms.request()).isGranted;
  static Future<bool> schedule({required Customer customer, required SmsTemplate template}) async {
    if (customer.phone.trim().isEmpty || customer.nextServiceDate.trim().isEmpty) return false;
    final when = parseServiceDate(customer.nextServiceDate);
    if (when == null || when.isBefore(DateTime.now())) return false;
    if (!(await Permission.sms.status).isGranted) return false;
    final result = await _channel.invokeMethod<bool>('scheduleSms', {
      'id': customer.id.hashCode & 0x7fffffff,
      'phone': customer.phone.trim(),
      'message': renderTemplate(template.body, customer),
      'timeMillis': when.millisecondsSinceEpoch,
    });
    return result ?? false;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _storageKey = 'modiriat_service_customers_v1';
  static const _templatesKey = 'modiriat_service_sms_templates_v1';
  final List<Customer> _customers = [];
  final List<SmsTemplate> _templates = [];
  final _search = TextEditingController();
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    final rawTemplates = prefs.getString(_templatesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        _customers..clear()..addAll(decoded.map((e) => Customer.fromJson(Map<String, dynamic>.from(e))));
      } catch (_) {}
    }
    if (rawTemplates != null && rawTemplates.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTemplates) as List;
        _templates..clear()..addAll(decoded.map((e) => SmsTemplate.fromJson(Map<String, dynamic>.from(e))));
      } catch (_) {}
    }
    if (_templates.isEmpty) { _templates.addAll(defaultSmsTemplates()); await _saveTemplates(); }
    for (final customer in _customers) {
      if (customer.smsTemplateId.isEmpty) customer.smsTemplateId = _templates.first.id;
    }
    await _save();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_customers.map((e) => e.toJson()).toList()));
    if (mounted) setState(() {});
  }

  Future<void> _saveTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_templatesKey, jsonEncode(_templates.map((e) => e.toJson()).toList()));
    if (mounted) setState(() {});
  }

  SmsTemplate _templateFor(Customer c) => _templates.firstWhere((t) => t.id == c.smsTemplateId, orElse: () => _templates.first);
  Future<void> _scheduleCustomer(Customer c) async => SmsScheduler.schedule(customer: c, template: _templateFor(c));
  Future<void> _scheduleAll() async { for (final c in _customers) { await _scheduleCustomer(c); } }

  List<Customer> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _customers;
    return _customers.where((c) => c.name.toLowerCase().contains(q) || c.phone.toLowerCase().contains(q) || c.deviceType.toLowerCase().contains(q)).toList();
  }

  Future<void> _customerForm({Customer? customer}) async {
    final name = TextEditingController(text: customer?.name ?? '');
    final phone = TextEditingController(text: customer?.phone ?? '');
    final device = TextEditingController(text: customer?.deviceType ?? '');
    final notes = TextEditingController(text: customer?.notes ?? '');
    final nextDate = TextEditingController(text: customer?.nextServiceDate ?? '');
    var selectedTemplate = customer?.smsTemplateId.isNotEmpty == true ? customer!.smsTemplateId : _templates.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => StatefulBuilder(builder: (dc, setD) => AlertDialog(
        title: Text(customer == null ? 'مشتری جدید' : 'ویرایش مشتری'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'نام مشتری')),
          const SizedBox(height: 10),
          TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'شماره تماس')),
          const SizedBox(height: 10),
          TextField(controller: device, decoration: const InputDecoration(labelText: 'نوع دستگاه')),
          const SizedBox(height: 10),
          TextField(controller: nextDate, decoration: const InputDecoration(labelText: 'تاریخ سرویس بعدی', hintText: 'مثلاً 1405/08/20')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: selectedTemplate, decoration: const InputDecoration(labelText: 'فرمت پیامک یادآوری'), items: _templates.map((t) => DropdownMenuItem(value: t.id, child: Text(t.title))).toList(), onChanged: (v) { if (v != null) setD(() => selectedTemplate = v); }),
          const SizedBox(height: 10),
          TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیحات')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dc, true), child: const Text('ذخیره')),
        ],
      )),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final target = customer ?? Customer(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name.text.trim());
    target..name = name.text.trim()..phone = phone.text.trim()..deviceType = device.text.trim()..notes = notes.text.trim()..nextServiceDate = nextDate.text.trim()..smsTemplateId = selectedTemplate;
    if (customer == null) _customers.insert(0, target);
    await _save();
    await _scheduleCustomer(target);
  }

  Future<void> _backupDialog() async {
    final raw = jsonEncode({'customers': _customers.map((e) => e.toJson()).toList(), 'templates': _templates.map((e) => e.toJson()).toList()});
    await showDialog<void>(context: context, builder: (dc) => AlertDialog(
      title: const Text('بکاپ و بازیابی'),
      content: const Text('برای بکاپ، متن اطلاعات را کپی و در جای امن نگه دارید. برای بازیابی، متن بکاپ را در کلیپ‌بورد کپی کنید و «بازیابی» را بزنید.'),
      actions: [
        TextButton(onPressed: () async { await Clipboard.setData(ClipboardData(text: raw)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('بکاپ در کلیپ‌بورد کپی شد'))); }, child: const Text('کپی بکاپ')),
        FilledButton(onPressed: () async {
          final data = await Clipboard.getData('text/plain');
          try {
            final decoded = jsonDecode(data?.text ?? '');
            final restored = (((decoded is Map ? decoded['customers'] : decoded) as List)).map((e) => Customer.fromJson(Map<String, dynamic>.from(e))).toList();
            _customers..clear()..addAll(restored);
            if (decoded is Map && decoded['templates'] is List) _templates..clear()..addAll((decoded['templates'] as List).map((e) => SmsTemplate.fromJson(Map<String, dynamic>.from(e))));
            await _save(); await _saveTemplates(); await _scheduleAll();
            if (dc.mounted) Navigator.pop(dc);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('بازیابی انجام شد')));
          } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('متن بکاپ معتبر نیست'))); }
        }, child: const Text('بازیابی از کلیپ‌بورد')),
      ],
    ));
  }

  Future<void> _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(templates: _templates, onSave: _saveTemplates, onSmsPermissionEnabled: _scheduleAll)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مدیریت سرویس', style: TextStyle(fontWeight: FontWeight.bold)), actions: [
      IconButton(onPressed: _openSettings, tooltip: 'تنظیمات', icon: const Icon(Icons.settings_outlined)),
      IconButton(onPressed: _backupDialog, tooltip: 'بکاپ', icon: const Icon(Icons.cloud_download_outlined)),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => _customerForm(), icon: const Icon(Icons.person_add_alt_1), label: const Text('مشتری جدید')),
    body: _loading ? const Center(child: CircularProgressIndicator()) : Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'جستجو نام، شماره یا نوع دستگاه...'))),
      Expanded(child: _filtered.isEmpty ? const Center(child: Text('هنوز مشتری ثبت نشده')) : ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 90), itemCount: _filtered.length,
        itemBuilder: (context, index) { final c = _filtered[index]; return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name.characters.first)),
          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text([if (c.deviceType.isNotEmpty) 'نوع دستگاه: ${c.deviceType}', if (c.phone.isNotEmpty) c.phone, if (c.nextServiceDate.isNotEmpty) 'سرویس بعدی: ${c.nextServiceDate}', 'مانده: ${money(c.balance)} تومان'].join('\n')),
          isThreeLine: true, trailing: const Icon(Icons.chevron_left),
          onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(customer: c, templates: _templates, onChanged: _save, onEdit: () => _customerForm(customer: c), onSchedule: () => _scheduleCustomer(c)))); if (mounted) setState(() {}); },
        )); },
      )),
    ]),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.templates, required this.onSave, required this.onSmsPermissionEnabled});
  final List<SmsTemplate> templates;
  final Future<void> Function() onSave;
  final Future<void> Function() onSmsPermissionEnabled;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checking = false;
  bool _smsGranted = false;
  @override
  void initState() { super.initState(); _refreshPermission(); }
  Future<void> _refreshPermission() async { final s = await Permission.sms.status; if (mounted) setState(() => _smsGranted = s.isGranted); }
  Future<void> _enableSms() async {
    setState(() => _checking = true);
    final granted = await SmsScheduler.ensurePermission();
    if (granted) await widget.onSmsPermissionEnabled();
    if (mounted) { setState(() { _checking = false; _smsGranted = granted; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(granted ? 'ارسال خودکار پیامک فعال شد' : 'برای ارسال خودکار باید مجوز پیامک را بدهید'))); }
  }

  Future<void> _editTemplate({SmsTemplate? template}) async {
    final title = TextEditingController(text: template?.title ?? '');
    final body = TextEditingController(text: template?.body ?? 'سلام {نام}، زمان سرویس دستگاه {دستگاه} در تاریخ {تاریخ} رسیده است.');
    final ok = await showDialog<bool>(context: context, builder: (dc) => AlertDialog(
      title: Text(template == null ? 'فرمت پیام جدید' : 'ویرایش فرمت پیام'),
      content: SingleChildScrollView(child: Column(children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'نام فرمت')),
        const SizedBox(height: 10),
        TextField(controller: body, minLines: 4, maxLines: 8, decoration: const InputDecoration(labelText: 'متن پیام', helperText: 'متغیرها: {نام}  {دستگاه}  {تاریخ}')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(dc, true), child: const Text('ذخیره'))],
    ));
    if (ok != true || title.text.trim().isEmpty || body.text.trim().isEmpty) return;
    if (template == null) widget.templates.add(SmsTemplate(id: DateTime.now().microsecondsSinceEpoch.toString(), title: title.text.trim(), body: body.text.trim())); else { template..title = title.text.trim()..body = body.text.trim(); }
    await widget.onSave(); if (mounted) setState(() {});
  }
  Future<void> _deleteTemplate(SmsTemplate t) async { if (widget.templates.length <= 1) return; widget.templates.remove(t); await widget.onSave(); if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تنظیمات')),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => _editTemplate(), icon: const Icon(Icons.add), label: const Text('فرمت پیام')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('ارسال خودکار پیامک', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
        Text(_smsGranted ? 'فعال است؛ پیامک در تاریخ سرویس بعدی از سیم‌کارت پیش‌فرض گوشی ارسال می‌شود.' : 'برای ارسال خودکار از سیم‌کارت گوشی، یک‌بار مجوز پیامک را فعال کنید.'), const SizedBox(height: 12),
        FilledButton.icon(onPressed: _checking ? null : _enableSms, icon: Icon(_smsGranted ? Icons.check_circle : Icons.sms_outlined), label: Text(_smsGranted ? 'مجوز پیامک فعال است' : 'فعال‌سازی پیامک')),
      ]))),
      const SizedBox(height: 16), const Text('فرمت‌های پیامک', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
      ...widget.templates.map((t) => Card(child: ListTile(title: Text(t.title), subtitle: Text(t.body), onTap: () => _editTemplate(template: t), trailing: widget.templates.length > 1 ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteTemplate(t)) : null))),
      const SizedBox(height: 90),
    ]),
  );
}

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customer, required this.templates, required this.onChanged, required this.onEdit, required this.onSchedule});
  final Customer customer;
  final List<SmsTemplate> templates;
  final Future<void> Function() onChanged;
  final Future<void> Function() onEdit;
  final Future<void> Function() onSchedule;
  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Customer get c => widget.customer;
  SmsTemplate get template => widget.templates.firstWhere((t) => t.id == c.smsTemplateId, orElse: () => widget.templates.first);

  Future<void> _addService() async {
    final desc = TextEditingController(); final amount = TextEditingController(); final date = TextEditingController(text: today()); final next = TextEditingController(text: c.nextServiceDate);
    final ok = await showDialog<bool>(context: context, builder: (dc) => AlertDialog(
      title: const Text('ثبت سرویس'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: desc, decoration: const InputDecoration(labelText: 'شرح سرویس')), const SizedBox(height: 10),
        TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ (تومان)')), const SizedBox(height: 10),
        TextField(controller: date, decoration: const InputDecoration(labelText: 'تاریخ')), const SizedBox(height: 10),
        TextField(controller: next, decoration: const InputDecoration(labelText: 'تاریخ سرویس بعدی', hintText: 'مثلاً 1405/08/20')),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(dc, true), child: const Text('ثبت'))],
    ));
    if (ok != true || desc.text.trim().isEmpty) return;
    c.services.insert(0, ServiceRecord(date: date.text.trim(), description: desc.text.trim(), amount: parseMoney(amount.text), nextDate: next.text.trim()));
    if (next.text.trim().isNotEmpty) c.nextServiceDate = next.text.trim();
    await widget.onChanged(); await widget.onSchedule(); if (mounted) setState(() {});
  }

  Future<void> _addPayment() async {
    final amount = TextEditingController(); final note = TextEditingController(); final date = TextEditingController(text: today());
    final ok = await showDialog<bool>(context: context, builder: (dc) => AlertDialog(
      title: const Text('ثبت پرداخت'), content: SingleChildScrollView(child: Column(children: [
        TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ (تومان)')), const SizedBox(height: 10),
        TextField(controller: date, decoration: const InputDecoration(labelText: 'تاریخ')), const SizedBox(height: 10),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیح')),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(dc, true), child: const Text('ثبت'))],
    ));
    if (ok != true || parseMoney(amount.text) <= 0) return;
    c.payments.insert(0, PaymentRecord(date: date.text.trim(), amount: parseMoney(amount.text), note: note.text.trim())); await widget.onChanged(); if (mounted) setState(() {});
  }

  Future<void> _addInvoice() async {
    final title = TextEditingController(text: 'فاکتور خدمات'); final date = TextEditingController(text: today()); final notes = TextEditingController(); final rows = <InvoiceDraftRow>[InvoiceDraftRow()];
    final ok = await showDialog<bool>(context: context, builder: (dc) => StatefulBuilder(builder: (dc, setD) => AlertDialog(
      title: const Text('فاکتور جدید'), content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان فاکتور')), const SizedBox(height: 10),
        TextField(controller: date, decoration: const InputDecoration(labelText: 'تاریخ')), const SizedBox(height: 14),
        ...rows.asMap().entries.map((entry) { final i = entry.key; final row = entry.value; return Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(padding: const EdgeInsets.all(10), child: Column(children: [
          TextField(controller: row.description, decoration: InputDecoration(labelText: 'شرح ردیف ${i + 1}')), const SizedBox(height: 8),
          TextField(controller: row.amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ (تومان)')),
          if (rows.length > 1) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setD(() => rows.removeAt(i)), icon: const Icon(Icons.delete_outline), label: const Text('حذف ردیف'))),
        ]))); }),
        OutlinedButton.icon(onPressed: () => setD(() => rows.add(InvoiceDraftRow())), icon: const Icon(Icons.add), label: const Text('افزودن ردیف')), const SizedBox(height: 10),
        TextField(controller: notes, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'توضیحات فاکتور')),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(dc, true), child: const Text('ذخیره فاکتور'))],
    )));
    if (ok != true) return;
    final items = rows.where((r) => r.description.text.trim().isNotEmpty).map((r) => InvoiceItem(description: r.description.text.trim(), amount: parseMoney(r.amount.text))).toList();
    if (items.isEmpty) return;
    c.invoices.insert(0, InvoiceRecord(id: DateTime.now().microsecondsSinceEpoch.toString(), date: date.text.trim(), title: title.text.trim().isEmpty ? 'فاکتور خدمات' : title.text.trim(), items: items, notes: notes.text.trim()));
    await widget.onChanged(); if (mounted) setState(() {});
  }

  Future<void> _shareInvoice(InvoiceRecord i) async { final bytes = await buildInvoicePdf(c, i); await Printing.sharePdf(bytes: bytes, filename: 'invoice-${i.id}.pdf'); }
  Future<void> _previewInvoice(InvoiceRecord i) async { final bytes = await buildInvoicePdf(c, i); await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'invoice-${i.id}.pdf'); }

  Future<void> _showSmsPreview() async {
    final text = renderTemplate(template.body, c);
    await showDialog<void>(context: context, builder: (dc) => AlertDialog(title: const Text('پیش‌نمایش پیامک'), content: SelectableText(text), actions: [
      TextButton(onPressed: () async { await Clipboard.setData(ClipboardData(text: text)); if (dc.mounted) Navigator.pop(dc); }, child: const Text('کپی متن')),
      FilledButton(onPressed: () async { final granted = await SmsScheduler.ensurePermission(); if (granted) await widget.onSchedule(); if (dc.mounted) Navigator.pop(dc); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(granted ? 'پیامک برای تاریخ سرویس بعدی زمان‌بندی شد' : 'مجوز پیامک داده نشد'))); }, child: const Text('زمان‌بندی خودکار')),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final summary = [if (c.deviceType.isNotEmpty) 'نوع دستگاه: ${c.deviceType}', if (c.phone.isNotEmpty) 'شماره: ${c.phone}', if (c.nextServiceDate.isNotEmpty) 'سرویس بعدی: ${c.nextServiceDate}', 'قالب پیامک: ${template.title}'].join('\n');
    return Scaffold(
      appBar: AppBar(title: Text(c.name), actions: [IconButton(onPressed: () async { await widget.onEdit(); if (mounted) setState(() {}); }, icon: const Icon(Icons.edit_outlined))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(c.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(summary),
          if (c.notes.isNotEmpty) ...[const SizedBox(height: 8), Text('توضیحات: ${c.notes}')], const Divider(height: 28),
          Text('جمع خدمات: ${money(c.totalServices)} تومان'), Text('جمع پرداخت‌ها: ${money(c.totalPayments)} تومان'), Text('مانده حساب: ${money(c.balance)} تومان', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]))), const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: _addService, icon: const Icon(Icons.build_outlined), label: const Text('ثبت سرویس')),
          OutlinedButton.icon(onPressed: _addPayment, icon: const Icon(Icons.payments_outlined), label: const Text('ثبت پرداخت')),
          OutlinedButton.icon(onPressed: _addInvoice, icon: const Icon(Icons.receipt_long_outlined), label: const Text('فاکتور جدید')),
          OutlinedButton.icon(onPressed: _showSmsPreview, icon: const Icon(Icons.sms_outlined), label: const Text('پیامک یادآوری')),
        ]),
        const SizedBox(height: 22), const Text('فاکتورها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
        if (c.invoices.isEmpty) const Card(child: ListTile(title: Text('فاکتوری ثبت نشده'))) else ...c.invoices.map((i) => Card(child: ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined), title: Text(i.title), subtitle: Text('${i.date}\nجمع: ${money(i.total)} تومان'), isThreeLine: true,
          trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'preview') _previewInvoice(i); if (v == 'share') _shareInvoice(i); }, itemBuilder: (_) => const [PopupMenuItem(value: 'preview', child: Text('مشاهده / ذخیره PDF')), PopupMenuItem(value: 'share', child: Text('ارسال PDF'))]),
        ))),
        const SizedBox(height: 22), const Text('سابقه خدمات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
        if (c.services.isEmpty) const Card(child: ListTile(title: Text('سرویسی ثبت نشده'))) else ...c.services.map((s) => Card(child: ListTile(title: Text(s.description), subtitle: Text([s.date, if (s.nextDate.isNotEmpty) 'سرویس بعدی: ${s.nextDate}'].join('\n')), trailing: Text('${money(s.amount)}\nتومان')))),
        const SizedBox(height: 22), const Text('پرداخت‌ها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 8),
        if (c.payments.isEmpty) const Card(child: ListTile(title: Text('پرداختی ثبت نشده'))) else ...c.payments.map((p) => Card(child: ListTile(title: Text('${money(p.amount)} تومان'), subtitle: Text([p.date, if (p.note.isNotEmpty) p.note].join('\n'))))),
        const SizedBox(height: 40),
      ]),
    );
  }
}

class InvoiceDraftRow { final description = TextEditingController(); final amount = TextEditingController(); }

List<SmsTemplate> defaultSmsTemplates() => [
  SmsTemplate(id: 'default-general', title: 'عمومی', body: 'سلام {نام} عزیز، زمان سرویس دستگاه {دستگاه} شما در تاریخ {تاریخ} رسیده است. لطفاً برای هماهنگی با ما تماس بگیرید.'),
  SmsTemplate(id: 'default-periodic', title: 'سرویس دوره‌ای', body: 'مشتری گرامی {نام}، یادآوری سرویس دوره‌ای دستگاه {دستگاه}: تاریخ سرویس {تاریخ}. برای حفظ عملکرد مناسب دستگاه، لطفاً زمان سرویس را هماهنگ کنید.'),
  SmsTemplate(id: 'default-urgent', title: 'دستگاه حساس', body: 'سلام {نام}، یادآوری مهم: موعد بررسی و سرویس دستگاه {دستگاه} در تاریخ {تاریخ} فرا رسیده است. لطفاً در اولین فرصت هماهنگ کنید.'),
];

String renderTemplate(String body, Customer c) => body.replaceAll('{نام}', c.name).replaceAll('{دستگاه}', c.deviceType).replaceAll('{تاریخ}', c.nextServiceDate);

DateTime? parseServiceDate(String raw) {
  final parts = raw.trim().replaceAll('-', '/').replaceAll('.', '/').replaceAll(' ', '').split('/');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]), m = int.tryParse(parts[1]), d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  try { final base = y < 1700 ? Jalali(y, m, d).toDateTime() : DateTime(y, m, d); return DateTime(base.year, base.month, base.day, 9); } catch (_) { return null; }
}

double parseMoney(String v) => double.tryParse(v.replaceAll(',', '').replaceAll('٬', '').replaceAll(' ', '')) ?? 0;
String today() { final j = Jalali.fromDateTime(DateTime.now()); return '${j.year.toString().padLeft(4, '0')}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}'; }
String money(num value) { final integer = value.round().toString(); final b = StringBuffer(); for (var i = 0; i < integer.length; i++) { final p = integer.length - i; b.write(integer[i]); if (p > 1 && p % 3 == 1) b.write(','); } return b.toString(); }

Future<Uint8List> buildInvoicePdf(Customer c, InvoiceRecord i) async {
  final font = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'));
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(28), theme: pw.ThemeData.withFont(base: font, bold: font), textDirection: pw.TextDirection.rtl,
    header: (_) => pw.Container(padding: const pw.EdgeInsets.only(bottom: 12), decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 1.5, color: PdfColors.blueGrey700))), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('مدیریت سرویس', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)), pw.Text(i.title, style: const pw.TextStyle(fontSize: 18))])),
    build: (_) => [
      pw.SizedBox(height: 18), pw.Container(padding: const pw.EdgeInsets.all(14), decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(8)), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [pw.Text('مشتری: ${c.name}'), if (c.phone.isNotEmpty) pw.Text('شماره تماس: ${c.phone}'), if (c.deviceType.isNotEmpty) pw.Text('نوع دستگاه: ${c.deviceType}'), pw.Text('تاریخ فاکتور: ${i.date}')])),
      pw.SizedBox(height: 18), pw.Table.fromTextArray(headers: const ['شرح', 'مبلغ (تومان)'], data: i.items.map((x) => [x.description, money(x.amount)]).toList(), headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100), headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold), cellAlignment: pw.Alignment.centerRight, cellStyle: const pw.TextStyle(fontSize: 11), border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5)),
      pw.SizedBox(height: 14), pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.blueGrey700), borderRadius: pw.BorderRadius.circular(8)), child: pw.Text('جمع کل: ${money(i.total)} تومان', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)))),
      if (i.notes.isNotEmpty) ...[pw.SizedBox(height: 18), pw.Text('توضیحات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 6), pw.Text(i.notes)],
    ],
    footer: (ctx) => pw.Align(alignment: pw.Alignment.center, child: pw.Text('صفحه ${ctx.pageNumber} از ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))),
  ));
  return doc.save();
}
