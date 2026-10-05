from pathlib import Path

src = Path('lib/app_v12.dart')
x = src.read_text()

# Repair compact dialog closures and invoice list line from the source snapshot.
x = x.replace(']))));', '])));')
lines = x.splitlines()
for idx, line in enumerate(lines):
    if "_section('فاکتورهای صادرشده'" in line:
        lines[idx] = "    _section('فاکتورهای صادرشده', c.invoices.map((i) => ListTile(title: Text(i.title), subtitle: Text('${i.date} • ${money(i.total)}'), trailing: Wrap(spacing: 0, children: [IconButton(onPressed: () => _pdf(i), icon: const Icon(Icons.picture_as_pdf_outlined)), IconButton(onPressed: () => _invoiceForm(invoice: i), icon: const Icon(Icons.edit_outlined))]))).toList()),"
x = '\n'.join(lines) + '\n'

anchor = "String newId() => DateTime.now().microsecondsSinceEpoch.toString();\n"
formatter = """

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final formatted = groupDigits(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

String groupDigits(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.replaceAllMapped(RegExp(r'\\B(?=(\\d{3})+(?!\\d))'), (m) => ',');
}
"""
if 'class ThousandsSeparatorInputFormatter' not in x:
    x = x.replace(anchor, anchor + formatter)

x = x.replace(
    "e.value.amount==0?'':e.value.amount.toStringAsFixed(0)",
    "e.value.amount==0?'':groupDigits(e.value.amount.toStringAsFixed(0))",
)
x = x.replace(
    "Expanded(flex:2,child:TextField(controller:dc,decoration:const InputDecoration(labelText:'شرح'),onChanged:(v)=>e.value.description=v))",
    "Expanded(flex:3,child:TextField(controller:dc,decoration:const InputDecoration(labelText:'شرح'),onChanged:(v)=>e.value.description=v))",
)
x = x.replace(
    "Expanded(child:TextField(controller:ac,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'مبلغ'),onChanged:(v)=>e.value.amount=double.tryParse(v.replaceAll(',',''))??0))",
    "Expanded(flex:3,child:TextField(controller:ac,keyboardType:TextInputType.number,inputFormatters:[ThousandsSeparatorInputFormatter()],textAlign:TextAlign.center,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w700),decoration:const InputDecoration(labelText:'مبلغ (تومان)',hintText:'مثلاً 1,250,000'),onChanged:(v)=>e.value.amount=double.tryParse(v.replaceAll(',',''))??0))",
)

src.write_text(x)
