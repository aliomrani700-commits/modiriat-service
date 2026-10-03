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
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مدیریت سرویس')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          MenuCard(title: 'مشتری جدید'),
          MenuCard(title: 'پرونده مشتری'),
          MenuCard(title: 'ثبت سرویس'),
          MenuCard(title: 'فاکتور و پرداخت'),
        ],
      ),
    );
  }
}

class MenuCard extends StatelessWidget {
  final String title;
  const MenuCard({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: const Icon(Icons.arrow_forward_ios),
      ),
    );
  }
}
