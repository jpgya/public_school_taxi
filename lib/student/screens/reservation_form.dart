import 'package:flutter/material.dart';

class ReservationForm extends StatefulWidget {
  const ReservationForm({super.key,
    required this.selectedDate,
    this.goSchool = false,
    this.backSchool = false,
    this.backTime,
  });

  final bool goSchool;
  final bool backSchool;
  final String? backTime;
  final DateTime selectedDate;

  @override
  State<StatefulWidget> createState() => _ReservationFormState();
}

class _ReservationFormState extends State<ReservationForm> {
  bool goSchool = false, backSchool = false;
  String? backTime;
  final times = ['12:00', '13:00', '16:00', '17:00'];

  @override
  void initState() {
    super.initState();
    goSchool = widget.goSchool;
    backSchool = widget.backSchool;
    backTime = widget.backTime;
  }

  @override
  Widget build(BuildContext c) => Padding(
    padding: EdgeInsets.all(24),
    child: SingleChildScrollView(
      child: Column( mainAxisSize: MainAxisSize.min,children: [
        Text(
          '${widget.selectedDate.month}月${widget.selectedDate.day}日(${['月', '火', '水', '木', '金', '土', '日'][(widget.selectedDate.weekday - 1) % 7]}) の予約',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        CheckboxListTile(
            title: Text('登校'),
            value: goSchool,
            onChanged: (v) => setState(() => goSchool = v!)),
        CheckboxListTile(
            title: Text('下校'),
            value: backSchool,
            onChanged: (v) => setState(() => backSchool = v!)),
        if (backSchool)
          ...times.map((t) => RadioListTile<String>(
              title: Text(t),
              value: t,
              groupValue: backTime,
              onChanged: (v) => setState(() => backTime = v))),
        SizedBox(height: 16),
        ElevatedButton(
            onPressed: () {
              if (backSchool && backTime == null) {
              } else {
                Navigator.pop(context, {
                  'goSchool': goSchool,
                  'backSchool': backSchool,
                  'backTime': backTime,
                });
              }
            },
            child: Text('変更'))
      ]),
    ),
  );
}