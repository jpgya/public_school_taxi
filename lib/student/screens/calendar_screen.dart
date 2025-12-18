import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// 適切なパスにご自身のプロジェクトに合わせて修正してください
import '../models/map.dart';


class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<StatefulWidget> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  // --- State Variables ---
  final Map<DateTime, List<DocumentSnapshot>> _events = {};
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;


  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  String? _currentUserSchoolId;

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _initialize();
  }

  /// 初期化処理
  Future<void> _initialize() async {
    setState(() => _isLoading = true);
    await _loadUserInfo();
    await _loadEventsForMonth();
    setState(() => _isLoading = false);
  }

  /// ログインユーザーの付随情報（学校ID）を読み込む
  Future<void> _loadUserInfo() async {
    if (_currentUserId == null) return;
    try {
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(_currentUserId).get();
      if (userDoc.exists) {
        _currentUserSchoolId = userDoc.data()?['schoolId'] as String?;
      }
    } catch (e) {
      debugPrint("ユーザー情報の読み込みエラー: $e");
    }
  }

  /// カレンダーに表示するための予約情報を月単位で読み込む
  Future<void> _loadEventsForMonth() async {
    if (_currentUserId == null) {
      if (mounted) setState(() => _errorMessage = "ログインしていません。");
      return;
    }

    if (mounted) setState(() => _isLoading = true);
    _events.clear();

    try {
      final startOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
      final endOfMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 0, 23, 59, 59);

      final reservationsSnap = await FirebaseFirestore.instance
          .collection('reservations')
          .where('userId', isEqualTo: _currentUserId)
          .where('pickUpTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .where('pickUpTime', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
          .get();

      for (var doc in reservationsSnap.docs) {
        final pickUpTime = (doc.data()['pickUpTime'] as Timestamp).toDate();
        final day = DateTime.utc(pickUpTime.year, pickUpTime.month, pickUpTime.day);
        _events.putIfAbsent(day, () => []).add(doc);
      }
    } catch (e) {
      debugPrint("予約の読み込みエラー: $e");
      if (mounted) _errorMessage = "予約の読み込みに失敗しました。";
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 日付セルがタップされた時のメインの処理
  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
      });
    }

    final dayUtc = DateTime.utc(selectedDay.year, selectedDay.month, selectedDay.day);
    final dayEvents = _events[dayUtc] ?? [];

    _showReservationSheetForDay(selectedDay, dayEvents);
  }

  /// 予約の有無や日付に応じて適切なモーダルシートを表示する
  void _showReservationSheetForDay(DateTime date, List<DocumentSnapshot> reservations) {
    final isPast = date.isBefore(DateUtils.dateOnly(DateTime.now()));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        // 予約がなく、かつ未来の日付の場合 -> 新規予約画面
        if (reservations.isEmpty && !isPast) {
          return _buildAddReservationSheet(date);
        }
        // 予約がある場合 -> 予約詳細リスト画面
        return _buildReservationListSheet(date, reservations, isPast);
      },
    );
  }


  /// 予約リストを表示するモーダル
  Widget _buildReservationListSheet(DateTime date, List<DocumentSnapshot> reservations, bool isPast) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(DateFormat.yMEd('ja').format(date), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(isPast ? "過去の予約" : "予約内容", style: Theme.of(context).textTheme.titleMedium),
          const Divider(height: 24),
          if (reservations.isEmpty)
            const Center(child: Text("この日の予約はありません。")),
          ...reservations.map((res) {
            final data = res.data() as Map<String, dynamic>;
            final isGo = data['goSchool'] as bool;
            final pickUpTime = (data['pickUpTime'] as Timestamp).toDate();
            final canModify = !isPast && DateTime.now().isBefore(pickUpTime);

            return ListTile(
              leading: Icon(isGo ? Icons.wb_sunny_rounded : Icons.nightlight_round, color: isGo ? Colors.orange : Colors.blue),
              title: Text(isGo ? '登校' : '下校'),
              subtitle: Text(DateFormat.Hm().format(pickUpTime)),
              trailing: canModify ? const Icon(Icons.info_outline) : null,
              onTap: canModify
                  ? () {
                Navigator.pop(context); // 現在のモーダルを閉じる
                _showEditOrDeleteReservationSheet(res);
                // 編集/削除モーダルを開く
              }
                  : null,
            );


          }).toList(),
          const SizedBox(height: 16),
          if (reservations.isNotEmpty && isPast)
            const Center(
              child: Text("過去の予約は変更・削除できません。", style: TextStyle(color: Colors.grey)),
            ),

        ],
      ),
    );
  }



  /// 新規予約を追加するモーダル
  Widget _buildAddReservationSheet(DateTime date) {


    if (_currentUserSchoolId == null) {
      return _buildInfoContent(context, date, 'ユーザー情報が読み込めないため予約できません。');
    }


    bool goSchool = false;
    bool backSchool = false;
    final List<TimeOfDay> backSchoolTimes = [
      const TimeOfDay(hour: 16, minute: 0), const TimeOfDay(hour: 17, minute: 0),
      const TimeOfDay(hour: 18, minute: 0), const TimeOfDay(hour: 19, minute: 0),
    ];
    TimeOfDay selectedBackSchoolTime = backSchoolTimes.first;

    return StatefulBuilder(builder: (context, setModalState) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat.yMEd('ja').format(date), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text("新しい予約を追加", style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 24),
            CheckboxListTile(
              title: const Text('登校'),
              secondary: const Icon(Icons.wb_sunny_rounded, color: Colors.orange),
              value: goSchool,
              onChanged: (val) => setModalState(() => goSchool = val!),
            ),
            CheckboxListTile(
              title: const Text('下校'),
              secondary: const Icon(Icons.nightlight_round, color: Colors.blue),
              value: backSchool,
              onChanged: (val) => setModalState(() => backSchool = val!),
            ),
            if (backSchool)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: DropdownButtonFormField<TimeOfDay>(
                  value: selectedBackSchoolTime,
                  items: backSchoolTimes.map((time) => DropdownMenuItem<TimeOfDay>(value: time, child: Text(time.format(context)))).toList(),
                  onChanged: (TimeOfDay? newValue) {
                    if (newValue != null) setModalState(() => selectedBackSchoolTime = newValue);
                  },
                  decoration: const InputDecoration(labelText: '下校時刻', border: OutlineInputBorder()),
                ),
              ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('予約を確定する'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                onPressed: (goSchool || backSchool) ? () => _addOrUpdateReservation(date: date, go: goSchool, back: backSchool, backTime: selectedBackSchoolTime) : null,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    });
  }


  /// 予約の編集または削除を行うモーダル
  void _showEditOrDeleteReservationSheet(DocumentSnapshot reservationDoc) {
    final data = reservationDoc.data() as Map<String, dynamic>;
    final isGo = data['goSchool'] as bool;
    final pickUpTime = (data['pickUpTime'] as Timestamp).toDate();

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${DateFormat.yMEd('ja').format(pickUpTime)} の${isGo ? '登校' : '下校'}予約', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              // ★★★ マップ確認ボタンを追加 ★★★
              if (data['assignedDriverId'] != null)
                ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: const Text('マップで現在地を確認'),
                  onTap: () {
                    final routeDocId = '${data['schoolId']}_${DateFormat('yyyy-MM-dd').format(pickUpTime)}_${isGo ? 'go' : 'back'}';
                    Navigator.pop(context); // モーダルを閉じる
                    Navigator.push(context, MaterialPageRoute(builder: (context) => RouteTrackingMapScreen(routeDocId: routeDocId , selectedDate: DateFormat('yyyy-MM-dd').format(pickUpTime))));
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit_calendar_outlined),
                title: const Text('予約を変更する'),
                onTap: () {
                  Navigator.pop(context);
                  _buildAddReservationSheet(pickUpTime); // 変更は新規追加と同じUIを再利用
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_forever_outlined, color: Colors.red.shade700),
                title: Text('予約を削除する', style: TextStyle(color: Colors.red.shade700)),
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('予約の削除'),
                      content: Text('${DateFormat.yMEd('ja').format(pickUpTime)}の${isGo ? '登校' : '下校'}予約を削除しますか？'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('キャンセル')),
                        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('削除'), style: TextButton.styleFrom(foregroundColor: Colors.red)),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    _deleteReservation(reservationDoc.id);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 予約を追加または更新する（Firestoreへの書き込み）
  Future<void> _addOrUpdateReservation({required DateTime date, bool? go, bool? back, TimeOfDay? backTime}) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // 同じ日の既存の予約を一旦削除する（更新処理のため）
      final dayUtc = DateTime.utc(date.year, date.month, date.day);
      final existingEvents = _events[dayUtc] ?? [];
      for (final event in existingEvents) {
        batch.delete(event.reference);
      }

      if (go == true) {
        final goPickUpTime = DateTime(date.year, date.month, date.day, 8, 30);
        batch.set(FirebaseFirestore.instance.collection('reservations').doc(), {
          'userId': _currentUserId, 'schoolId': _currentUserSchoolId,
          'pickUpTime': Timestamp.fromDate(goPickUpTime),
          'goSchool': true, 'backSchool': false, 'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'assignedDriverId': null, 'pickUpOrder': null,
        });
      }
      if (back == true && backTime != null) {
        final backPickUpTime = DateTime(date.year, date.month, date.day, backTime.hour, backTime.minute);
        batch.set(FirebaseFirestore.instance.collection('reservations').doc(), {
          'userId': _currentUserId, 'schoolId': _currentUserSchoolId,
          'pickUpTime': Timestamp.fromDate(backPickUpTime),
          'goSchool': false, 'backSchool': true, 'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'assignedDriverId': null, 'pickUpOrder': null,
        });
      }

      await batch.commit();
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('予約を更新しました。'), backgroundColor: Colors.green));
      _initialize();
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('予約の更新に失敗しました: $e'), backgroundColor: Colors.red));
    }
  }

  /// 予約を削除する（Firestoreからの削除）
  Future<void> _deleteReservation(String docId) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('reservations').doc(docId).delete();
      navigator.pop(); // モーダルを閉じる
      messenger.showSnackBar(const SnackBar(content: Text('予約を削除しました。'), backgroundColor: Colors.blue));
      _initialize(); // カレンダーを更新
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('予約の削除に失敗しました: $e'), backgroundColor: Colors.red));
    }
  }

  // --- UI Builder Widgets ---

  Widget _buildInfoContent(BuildContext context, DateTime date, String message) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(DateFormat.yMEd('ja').format(date), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack( // 更新ボタンをカレンダーの上に配置するためにStackを使用
        children: [
          Column(
            children: [
              Expanded(
                child: TableCalendar<DocumentSnapshot>(
                  locale: 'ja_JP',
                  firstDay: DateTime.utc(2022, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  rowHeight: 65, // 高さを調整して長方形に
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: _onDaySelected,
                  onPageChanged: (focusedDay) {
                    if (!isSameDay(_focusedDay, focusedDay)) {
                      setState(() => _focusedDay = focusedDay);
                      _loadEventsForMonth();
                    }
                  },
                  eventLoader: (day) => _events[DateTime.utc(day.year, day.month, day.day)] ?? [],
                  headerStyle: const HeaderStyle(titleCentered: true, formatButtonVisible: false),
                  calendarBuilders: CalendarBuilders(
                    markerBuilder: (context, day, events) {
                      if (events.isEmpty) return null;
                      return Positioned(
                        right: 4, bottom: 4,
                        child: Row(
                          children: [
                            if (events.any((e) => (e.data() as Map)['goSchool'] == true))
                              Container(width: 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.orange)),
                            if (events.any((e) => (e.data() as Map)['backSchool'] == true))
                              Container(width: 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.blue)),
                          ],
                        ),
                      );
                    },
                    defaultBuilder: (context, day, focusedDay) => Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300), right: BorderSide(color: Colors.grey.shade300))),
                      child: Text('${day.day}'),
                    ),
                    todayBuilder: (context, day, focusedDay) => Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.amber.shade100, border: Border(bottom: BorderSide(color: Colors.grey.shade300), right: BorderSide(color: Colors.grey.shade300))),
                      child: Text('${day.day}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    selectedBuilder: (context, day, focusedDay) => Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, border: Border(bottom: BorderSide(color: Colors.grey.shade300), right: BorderSide(color: Colors.grey.shade300))),
                      child: Text('${day.day}', style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer)),
                    ),
                    outsideBuilder: (context, day, focusedDay) => Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(bottom: BorderSide(color: Colors.grey.shade300), right: BorderSide(color: Colors.grey.shade300))),
                      child: Text('${day.day}', style: TextStyle(color: Colors.grey.shade400)),
                    ),
                  ),
                ),
              ),
              if (_isLoading) const LinearProgressIndicator(),
            ],
          ),
          // ★★★ 孤立した更新ボタン ★★★
          if (!_isLoading)
            Positioned(
              top: 8,
              right: 60,
              child: FloatingActionButton(
                mini: true,
                onPressed: _initialize,
                tooltip: 'カレンダーを更新',
                child: const Icon(Icons.refresh),
              ),
            ),
        ],
      ),
      // floatingActionButton: FloatingActionButton(
      //   onPressed: () => _onDaySelected(DateTime.now(), DateTime.now()),
      //   tooltip: '今日の予約',
      //   child: const Icon(Icons.today),
      // ),
    );
  }
}
