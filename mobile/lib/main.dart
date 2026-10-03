import 'package:flutter/material.dart';

void main() {
  runApp(const ModiriatServiceApp());
}

class ModiriatServiceApp extends StatelessWidget {
  const ModiriatServiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مدیریت سرویس',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('مدیریت سرویس')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            ListTile(title: Text('مشتری‌ها')),
            ListTile(title: Text('پرونده مشتری')),
            ListTile(title: Text('ثبت سرویس')),
            ListTile(title: Text('فاکتور و پرداخت')),
          ],
        ),
      ),
    );
  }
}
