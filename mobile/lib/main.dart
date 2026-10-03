import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class Customer {
  Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.vehicle = '',
    this.notes = '',
    this.nextServiceDate = '',
    List<ServiceRecord>? services,
    List<PaymentRecord>? payments,
  })  : services = services ?? [],
        payments = payments ?? [];

  String id;
  String name;
  String phone;
  String vehicle;
  String notes;
  String nextServiceDate;
  List<ServiceRecord> services;
  List<PaymentRecord> payments;

  double get totalServices => services.fold(0, (sum, item) => sum + item.amount);
  double get totalPayments => payments.fold(0, (sum, item) => sum + item.amount);
  double get balance => totalServices - totalPayments;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'vehicle': vehicle,
        'notes': notes,
        'nextServiceDate': nextServiceDate,
        'services': services.map((e) => e.toJson()).toList(),
        'payments': payments.map((e) => e.toJson()).toList(),
      };

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        vehicle: json['vehicle']?.toString() ?? '',
        notes: json['notes']?.toString() ?? '',
        nextServiceDate: json['nextServiceDate']?.toString() ?? '',
        services: ((json['services'] as List?) ?? [])
            .map((e) => ServiceRecord.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        payments: ((json['payments'] as List?) ?? [])
            .map((e) => PaymentRecord.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class ServiceRecord {
  ServiceRecord({
    required this.date,
    required this.description,
    required this.amount,
    this.nextDate = '',
  });

  String date;
  String description;
  double amount;
  String nextDate;

  Map<String, dynamic> toJson() => {
        'date': date,
        'description': description,
        'amount': amount,
        'nextDate': nextDate,
      };

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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _storageKey = 'modiriat_service_customers_v1';
  final List<Customer> _customers = [];
  final _search = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        _customers
          ..clear()
          ..addAll(decoded.map((e) => Customer.fromJson(Map<String, dynamic>.from(e))));
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_customers.map((e) => e.toJson()).toList()));
    if (mounted) setState(() {});
  }

  List<Customer> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _customers;
    return _customers.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q) ||
          c.vehicle.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _customerForm({Customer? customer}) async {
    final name = TextEditingController(text: customer?.name ?? '');
    final phone = TextEditingController(text: customer?.phone ?? '');
    final vehicle = TextEditingController(text: customer?.vehicle ?? '');
    final notes = TextEditingController(text: customer?.notes ?? '');
    final nextDate = TextEditingController(text: customer?.nextServiceDate ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(customer == null ? 'مشتری جدید' : 'ویرایش مشتری'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'نام مشتری')),
              const SizedBox(height: 10),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'شماره تماس')),
              const SizedBox(height: 10),
              TextField(controller: vehicle, decoration: const InputDecoration(labelText: 'خودرو / موتور / دستگاه')),
              const SizedBox(height: 10),
              TextField(controller: nextDate, decoration: const InputDecoration(labelText: 'تاریخ سرویس بعدی', hintText: 'مثلاً 1405/08/20')),
              const SizedBox(height: 10),
              TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'توضیحات')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ذخیره')),
        ],
      ),
    );

    if (ok != true || name.text.trim().isEmpty) return;
    if (customer == null) {
      _customers.insert(
        0,
        Customer(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name.text.trim(),
          phone: phone.text.trim(),
          vehicle: vehicle.text.trim(),
          notes: notes.text.trim(),
          nextServiceDate: nextDate.text.trim(),
        ),
      );
    } else {
      customer
        ..name = name.text.trim()
        ..phone = phone.text.trim()
        ..vehicle = vehicle.text.trim()
        ..notes = notes.text.trim()
        ..nextServiceDate = nextDate.text.trim();
    }
    await _save();
  }

  Future<void> _backupDialog() async {
    final raw = jsonEncode(_customers.map((e) => e.toJson()).toList());
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('بکاپ و بازیابی'),
        content: const Text('برای بکاپ، متن اطلاعات را کپی و در جای امن نگه دارید. برای بازیابی، متن بکاپ را در کلیپ‌بورد کپی کنید و «بازیابی» را بزنید.'),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: raw));
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('بکاپ در کلیپ‌بورد کپی شد')));
            },
            child: const Text('کپی بکاپ'),
          ),
          FilledButton(
            onPressed: () async {
              final data = await Clipboard.getData('text/plain');
              try {
                final decoded = jsonDecode(data?.text ?? '') as List;
                final restored = decoded.map((e) => Customer.fromJson(Map<String, dynamic>.from(e))).toList();
                _customers
                  ..clear()
                  ..addAll(restored);
                await _save();
                if (mounted) Navigator.pop(dialogContext);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('بازیابی انجام شد')));
              } catch (_) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('متن بکاپ معتبر نیست')));
              }
            },
            child: const Text('بازیابی از کلیپ‌بورد'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت سرویس', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _backupDialog, tooltip: 'بکاپ', icon: const Icon(Icons.cloud_download_outlined))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _customerForm(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('مشتری جدید'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'جستجو نام، شماره یا وسیله...'),
                  ),
                ),
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(child: Text('هنوز مشتری ثبت نشده'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final c = _filtered[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name.characters.first)),
                                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text([
                                  if (c.vehicle.isNotEmpty) c.vehicle,
                                  if (c.phone.isNotEmpty) c.phone,
                                  if (c.nextServiceDate.isNotEmpty) 'سرویس بعدی: ${c.nextServiceDate}',
                                  'مانده: ${money(c.balance)}',
                                ].join('\n')),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CustomerDetailScreen(
                                        customer: c,
                                        onChanged: _save,
                                        onEdit: () => _customerForm(customer: c),
                                      ),
                                    ),
                                  );
                                  setState(() {});
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.customer,
    required this.onChanged,
    required this.onEdit,
  });

  final Customer customer;
  final Future<void> Function() onChanged;
  final Future<void> Function() onEdit;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Customer get c => widget.customer;

  Future<void> _addService() async {
    final desc = TextEditingController();
    final amount = TextEditingController();
    final date = TextEditingController(text: today());
    final next = TextEditingController(text: c.nextServiceDate);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ثبت سرویس'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: desc, decoration: const InputDecoration(labelText: 'شرح سرویس')),
            const SizedBox(height: 10),
            TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ (تومان)')),
            const SizedBox(height: 10),
            TextField(controller: date, decoration: const InputDecoration(labelText: 'تاریخ')),
            const SizedBox(height: 10),
            TextField(controller: next, decoration: const InputDecoration(labelText: 'سرویس بعدی')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ثبت')),
        ],
      ),
    );
    if (ok != true || desc.text.trim().isEmpty) return;
    c.services.insert(
      0,
      ServiceRecord(
        date: date.text.trim(),
        description: desc.text.trim(),
        amount: double.tryParse(amount.text.replaceAll(',', '')) ?? 0,
        nextDate: next.text.trim(),
      ),
    );
    if (next.text.trim().isNotEmpty) c.nextServiceDate = next.text.trim();
    await widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _addPayment() async {
    final amount = TextEditingController();
    final note = TextEditingController();
    final date = TextEditingController(text: today());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ثبت پرداخت'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مبلغ (تومان)')),
            const SizedBox(height: 10),
            TextField(controller: date, decoration: const InputDecoration(labelText: 'تاریخ')),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'توضیحات')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ثبت')),
        ],
      ),
    );
    if (ok != true) return;
    final value = double.tryParse(amount.text.replaceAll(',', '')) ?? 0;
    if (value <= 0) return;
    c.payments.insert(0, PaymentRecord(date: date.text.trim(), amount: value, note: note.text.trim()));
    await widget.onChanged();
    if (mounted) setState(() {});
  }

  String _invoiceText() {
    final b = StringBuffer()
      ..writeln('فاکتور خدمات')
      ..writeln('مشتری: ${c.name}')
      ..writeln(ifNotEmpty('تماس: ', c.phone))
      ..writeln(ifNotEmpty('وسیله: ', c.vehicle))
      ..writeln('---------------------');
    for (final s in c.services.reversed) {
      b.writeln('${s.date} | ${s.description} | ${money(s.amount)}');
    }
    b
      ..writeln('---------------------')
      ..writeln('جمع خدمات: ${money(c.totalServices)}')
      ..writeln('جمع پرداخت: ${money(c.totalPayments)}')
      ..writeln('مانده حساب: ${money(c.balance)}');
    if (c.nextServiceDate.isNotEmpty) b.writeln('سرویس بعدی: ${c.nextServiceDate}');
    return b.toString();
  }

  Future<void> _showInvoice() async {
    final text = _invoiceText();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فاکتور / گزارش حساب'),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فاکتور کپی شد؛ می‌توانید برای مشتری ارسال کنید')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('کپی فاکتور'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyReminder() async {
    final dateText = c.nextServiceDate.isEmpty ? 'سرویس دوره‌ای' : 'سرویس دوره‌ای در تاریخ ${c.nextServiceDate}';
    final text = 'سلام ${c.name}، یادآوری $dateText. لطفاً برای هماهنگی سرویس با ما تماس بگیرید.';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('متن یادآوری کپی شد')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            onPressed: () async {
              await widget.onEdit();
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'ویرایش',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                if (c.phone.isNotEmpty) Text('تلفن: ${c.phone}'),
                if (c.vehicle.isNotEmpty) Text('وسیله: ${c.vehicle}'),
                if (c.notes.isNotEmpty) Text('توضیحات: ${c.notes}'),
                if (c.nextServiceDate.isNotEmpty) Text('سرویس بعدی: ${c.nextServiceDate}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _summary('جمع خدمات', money(c.totalServices))),
            const SizedBox(width: 8),
            Expanded(child: _summary('پرداخت‌ها', money(c.totalPayments))),
          ]),
          const SizedBox(height: 8),
          _summary('مانده حساب', money(c.balance)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: _addService, icon: const Icon(Icons.build_outlined), label: const Text('ثبت سرویس')),
            FilledButton.tonalIcon(onPressed: _addPayment, icon: const Icon(Icons.payments_outlined), label: const Text('ثبت پرداخت')),
            FilledButton.tonalIcon(onPressed: _showInvoice, icon: const Icon(Icons.receipt_long_outlined), label: const Text('فاکتور')),
            OutlinedButton.icon(onPressed: _copyReminder, icon: const Icon(Icons.sms_outlined), label: const Text('متن یادآوری')),
          ]),
          const SizedBox(height: 22),
          const Text('سابقه خدمات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (c.services.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('سرویسی ثبت نشده')))
          else
            ...c.services.map((s) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.build_circle_outlined),
                    title: Text(s.description),
                    subtitle: Text('${s.date}${s.nextDate.isEmpty ? '' : '\nسرویس بعدی: ${s.nextDate}'}'),
                    trailing: Text(money(s.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                )),
          const SizedBox(height: 18),
          const Text('پرداخت‌ها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (c.payments.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('پرداختی ثبت نشده')))
          else
            ...c.payments.map((p) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(money(p.amount)),
                    subtitle: Text('${p.date}${p.note.isEmpty ? '' : '\n${p.note}'}'),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _summary(String title, String value) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [Text(title), const SizedBox(height: 4), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))]),
        ),
      );
}

String money(double value) {
  final s = value.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return '${out.toString()} تومان';
}

String today() {
  final d = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)}';
}

String ifNotEmpty(String prefix, String value) => value.isEmpty ? '' : '$prefix$value';
