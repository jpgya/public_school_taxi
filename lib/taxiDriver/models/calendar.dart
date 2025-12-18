import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:school_taxi/taxiDriver/models/map.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../taxi_driver_map.dart';


class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.userId});
  final String? userId; // ドライバーのID

  @override
  State<StatefulWidget> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final Map<DateTime, List<String>> _events = {};
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  String? _currentUserCompanyId;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _initializeAndLoadEvents();
  }

  // ドライバの会社ID取得に特化
  Future<void> _initializeAndLoadEvents() async {
    if (widget.userId == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = "ユーザー情報が取得できません。";
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final driverDoc = await FirebaseFirestore.instance.collection('drivers').doc(widget.userId).get();
      if (!driverDoc.exists) {
        throw Exception("ドライバーのデータが見つかりません。");
      }
      final companyId = (driverDoc.data() as Map<String, dynamic>)['companyId'] as String?;
      if (companyId == null || companyId.isEmpty) {
        throw Exception("ドライバーに会社情報が紐付いていません。");
      }

      if (!mounted) return;
      _currentUserCompanyId = companyId;
      debugPrint("Acquired Company ID: $_currentUserCompanyId");

      // 会社ID取得後、イベント読み込みを開始
      await _loadEventsForMonth();

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = "初期化に失敗しました: ${e.toString().replaceAll('Exception: ', '')}";
      });
    }
  }

  // ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  // ★★★ ご指摘の正しいデータ構造に基づいて完全に書き直したメソッド ★★★
  // ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
  Future<void> _loadEventsForMonth() async {
    if (_currentUserCompanyId == null) {
      debugPrint("Company ID is not available. Cannot load events.");
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (mounted) setState(() => _isLoading = true);
    _events.clear();

    try {
      // 1. companyIdからmunicipalityIdを取得
      final companyDoc = await FirebaseFirestore.instance.collection('companys').doc(_currentUserCompanyId).get();
      if (!companyDoc.exists) throw Exception("会社情報が見つかりません。");

      final municipalityId = (companyDoc.data() as Map<String, dynamic>)['municipalityId'] as String?;
      if (municipalityId == null || municipalityId.isEmpty) throw Exception("会社に自治体IDが紐付いていません。");

      // 2. municipalityIdに紐づく全てのschoolIdを取得
      final schoolsSnap = await FirebaseFirestore.instance.collection('schools').where('municipalityId', isEqualTo: municipalityId).get();
      if (schoolsSnap.docs.isEmpty) {
        debugPrint("No schools found for municipalityId: $municipalityId");
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final schoolIds = schoolsSnap.docs.map((doc) => doc.id).toList();
      debugPrint("Found ${schoolIds.length} schools.");

      // 3. schoolIdリストに紐づく全てのuserIdを取得
      List<String> userIds = [];
      for (var i = 0; i < schoolIds.length; i += 30) { // whereInは30個までの制限
        final sublist = schoolIds.sublist(i, i + 30 > schoolIds.length ? schoolIds.length : i + 30);
        final usersSnap = await FirebaseFirestore.instance.collection('Users').where('schoolId', whereIn: sublist).get();
        userIds.addAll(usersSnap.docs.map((doc) => doc.id));
      }

      if (userIds.isEmpty) {
        debugPrint("No users found for the schools.");
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      debugPrint("Found ${userIds.length} users.");

      // 4. userIdリストを使って、その月の予約をまとめて取得
      final startOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
      final endOfMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 0, 23, 59, 59);

      List<Future<QuerySnapshot>> reservationFutures = [];
      for (var i = 0; i < userIds.length; i += 30) {
        final sublist = userIds.sublist(i, i + 30 > userIds.length ? userIds.length : i + 30);
        reservationFutures.add(
            FirebaseFirestore.instance.collection('reservations')
                .where('userId', whereIn: sublist)
                .where('pickUpTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
                .where('pickUpTime', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
                .get()
        );
      }

      final List<QuerySnapshot> reservationSnapshots = await Future.wait(reservationFutures);
      for (final snap in reservationSnapshots) {
        for (var doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final pickUpTime = (data['pickUpTime'] as Timestamp?)?.toDate();
          if (pickUpTime == null) continue;

          final day = DateTime.utc(pickUpTime.year, pickUpTime.month, pickUpTime.day);
          _events.putIfAbsent(day, () => []);

          if (data['goSchool'] == true && !_events[day]!.contains('go')) {
            _events[day]!.add('go');
          }
          if (data['backSchool'] == true && !_events[day]!.contains('back')) {
            _events[day]!.add('back');
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading events: $e");
      if (mounted) _errorMessage = "イベントの読み込みに失敗しました: ${e.toString().replaceAll('Exception: ', '')}";
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ★★★ こちらも同様に、正しいデータ構造に基づいて修正 ★★★
  // ... (他の部分は変更なし) ...

  // ★★★ こちらも同様に、正しいデータ構造に基づいて修正 ★★★
  // ... (他の部分は変更なし) ...

  // ★★★ こちらも同様に、正しいデータ構造に基づいて修正 ★★★
  Future<void> _showReservationDetails(DateTime date) async {
    if (_currentUserCompanyId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // --- 1. 関連する全userIdを取得 ---
      final companyDoc = await FirebaseFirestore.instance.collection('companys').doc(_currentUserCompanyId).get();
      final municipalityId = (companyDoc.data() as Map<String, dynamic>)['municipalityId'] as String?;
      final schoolsSnap = await FirebaseFirestore.instance.collection('schools').where('municipalityId', isEqualTo: municipalityId).get();
      final schoolIds = schoolsSnap.docs.map((doc) => doc.id).toList();

      List<String> userIds = [];
      for (var i = 0; i < schoolIds.length; i += 30) {
        final sublist = schoolIds.sublist(i, i + 30 > schoolIds.length ? schoolIds.length : i + 30);
        final usersSnap = await FirebaseFirestore.instance.collection('Users').where('schoolId', whereIn: sublist).get();
        userIds.addAll(usersSnap.docs.map((doc) => doc.id));
      }

      if (userIds.isEmpty) {
        if(mounted) Navigator.pop(context);
        showModalBottomSheet(context: context, builder: (context) => Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('${DateFormat.yMEd('ja_JP').format(date)}\n\nこの日の予約はありません。', textAlign: TextAlign.center))));
        return;
      }

      // --- 2. その日の予約を取得 ---
      final startOfDay = Timestamp.fromDate(DateTime(date.year, date.month, date.day));
      final endOfDay = Timestamp.fromDate(DateTime(date.year, date.month, date.day, 23, 59, 59));

      List<Future<QuerySnapshot>> reservationFutures = [];
      for (var i = 0; i < userIds.length; i += 30) {
        final sublist = userIds.sublist(i, i + 30 > userIds.length ? userIds.length : i + 30);
        reservationFutures.add(FirebaseFirestore.instance
            .collection('reservations')
            .where('userId', whereIn: sublist)
            .where('pickUpTime', isGreaterThanOrEqualTo: startOfDay)
            .where('pickUpTime', isLessThanOrEqualTo: endOfDay)
            .get());
      }

      final List<QuerySnapshot> reservationSnapshots = await Future.wait(reservationFutures);
      final List<DocumentSnapshot> dayReservations = [];
      for (final snap in reservationSnapshots) {
        dayReservations.addAll(snap.docs);
      }

      // ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
      // ★★★ ここからが予約をグループ化するロジックです (全面的に修正) ★★★
      // --- 3. 予約を「学校」と「登下校」でグループ化 ---
      Map<String, Map<String, dynamic>> groupedReservations = {};

      // 登校と下校のリストに分離
      final goSchoolReservations = dayReservations.where((doc) => (doc.data() as Map<String, dynamic>)['goSchool'] == true).toList();
      final backSchoolReservations = dayReservations.where((doc) => (doc.data() as Map<String, dynamic>)['backSchool'] == true).toList();

      // 【登校グループの処理】
      for (var resDoc in goSchoolReservations) {
        final resData = resDoc.data() as Map<String, dynamic>;
        final userId = resData['userId'] as String?;
        if (userId == null) continue;

        final userDoc = await FirebaseFirestore.instance.collection('Users').doc(userId).get();
        if (!userDoc.exists) continue;

        final schoolId = (userDoc.data()! as Map<String, dynamic>)['schoolId'] as String?;
        if (schoolId == null) continue;

        final groupKey = '${schoolId}_go'; // 登校用のキー

        if (!groupedReservations.containsKey(groupKey)) {
          final schoolDoc = await FirebaseFirestore.instance.collection('schools').doc(schoolId).get();
          String schoolName = '学校名不明';
          if (schoolDoc.exists && schoolDoc.data() != null) {
            final schoolData = schoolDoc.data() as Map<String, dynamic>;
            schoolName = schoolData['schoolName'] as String? ?? schoolData['name'] as String? ?? '学校名不明';
          }
          groupedReservations[groupKey] = {
            'schoolId': schoolId,
            'schoolName': schoolName,
            'isGoSchool': true,
            'reservationCount': 0,
            'pickUpTime': DateTime(date.year, date.month, date.day, 8, 30), // 登校は8:30固定
          };
        }
        groupedReservations[groupKey]!['reservationCount']++;
      }

      // 【下校グループの処理】
      for (var resDoc in backSchoolReservations) {
        final resData = resDoc.data() as Map<String, dynamic>;
        final userId = resData['userId'] as String?;
        if (userId == null) continue;

        final userDoc = await FirebaseFirestore.instance.collection('Users').doc(userId).get();
        if (!userDoc.exists) continue;

        final schoolId = (userDoc.data()! as Map<String, dynamic>)['schoolId'] as String?;
        if (schoolId == null) continue;

        final groupKey = '${schoolId}_back'; // 下校用のキー

        if (!groupedReservations.containsKey(groupKey)) {
          final schoolDoc = await FirebaseFirestore.instance.collection('schools').doc(schoolId).get();
          String schoolName = '学校名不明';
          if (schoolDoc.exists && schoolDoc.data() != null) {
            final schoolData = schoolDoc.data() as Map<String, dynamic>;
            schoolName = schoolData['schoolName'] as String? ?? schoolData['name'] as String? ?? '学校名不明';
          }
          groupedReservations[groupKey] = {
            'schoolId': schoolId,
            'schoolName': schoolName,
            'isGoSchool': false,
            'reservationCount': 0,
            'pickUpTime': (resData['pickUpTime'] as Timestamp).toDate(), // 下校は予約時刻
          };
        }
        groupedReservations[groupKey]!['reservationCount']++;
      }

      final List<Map<String, dynamic>> reservationGroups = groupedReservations.values.toList();

      // 表示順を整える（学校名 -> 登校/下校順）
      reservationGroups.sort((a, b) {
        int schoolComp = (a['schoolName'] as String).compareTo(b['schoolName'] as String);
        if (schoolComp != 0) return schoolComp;

        // ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
        // ★★★★★★★★★★ ここが修正箇所です ★★★★★★★★★★★★
        final isGoA = a['isGoSchool'] as bool;
        final isGoB = b['isGoSchool'] as bool;

        // bool型にはcompareToがないため、直接比較する
        if (isGoA && !isGoB) {
          return -1; // A(登校)がB(下校)より前
        } else if (!isGoA && isGoB) {
          return 1;  // B(登校)がA(下校)より前
        } else {
          return 0;  // どちらも登校 or どちらも下校
        }
        // ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★
      });
      // ★★★ ここまでがグループ化のロジックです ★★★
      // ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★

      if(mounted) Navigator.pop(context); // ローディングを閉じる

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            child: Builder(builder: (context) {
              if (reservationGroups.isEmpty) {
                return Center(child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('${DateFormat.yMEd('ja_JP').format(date)}\n\nこの日の予約はありません。', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                ));
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Text(
                      DateFormat.yMEd('ja_JP').format(date),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: reservationGroups.length, // グループの数
                      itemBuilder: (context, index) {
                        final group = reservationGroups[index];
                        final schoolName = group['schoolName'] as String;
                        final isGo = group['isGoSchool'] as bool;
                        final count = group['reservationCount'] as int;
                        final pickUpTime = group['pickUpTime'] as DateTime;

                        return Card( // グループごとにカードで囲む
                          margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                          child: ListTile(
                            leading: Icon(
                              isGo ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                              color: isGo ? Colors.orange : Colors.blue,
                              size: 32,
                            ),
                            title: Row(
                              children: [

                                Text(schoolName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            subtitle: Row(
                              children: [
                                const Icon(Icons.access_time_outlined, size: 16),
                                Text('${isGo ? '登校' : '下校'} - ${DateFormat('HH:mm').format(pickUpTime)}'),

                              ],
                            ),
                            trailing: Chip(
                              label: Text('$count 名'),
                              backgroundColor: Colors.grey.shade200,
                            ),
                            // ★★★ グループのタイルをタップしたときの動作 ★★★
                            onTap: () {
                              Navigator.pop(context); // モーダルを閉じる
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => MapScreen(
                                    selectedDate: date,
                                    schoolId: group['schoolId'],
                                    isGoSchool: isGo,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            }),
          );
        },
      );
    } catch(e) {
      if(mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('詳細の取得に失敗しました: $e'), backgroundColor: Colors.red));
    }
  }

// ... (buildメソッド以下は変更なし) ...



// ... (buildメソッド以下は変更なし)

  @override
  Widget build(BuildContext c) {
    // ボディ部分を生成する共通のウィジェット
    Widget body;

    if (_isLoading && _events.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_errorMessage != null) {
      body = Center(child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center,),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _initializeAndLoadEvents, child: const Text('再試行'))
          ],
        ),
      ));
    } else {
      // カレンダーとインジケーター
      body = Column(
        children: [
          // Expandedでラップしてオーバーフローを防ぐ
          Expanded(
            child: TableCalendar<String>(
              locale: 'ja_JP',
              firstDay: DateTime.now().subtract(const Duration(days: 365)),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              rowHeight: 80,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                _showReservationDetails(selectedDay);
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
                _loadEventsForMonth();
              },
              eventLoader: (day) {
                final dayUtc = DateTime.utc(day.year, day.month, day.day);
                return _events[dayUtc] ?? [];
              },
              headerStyle: const HeaderStyle(
                  titleCentered: true, titleTextStyle: TextStyle(fontSize: 24), formatButtonVisible: false),
              daysOfWeekHeight: 32,
              daysOfWeekStyle: DaysOfWeekStyle(
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300))),
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (ctx, d, f) {
                  return _buildDayCell(d, _events[DateTime.utc(d.year, d.month, d.day)]);
                },
                todayBuilder: (ctx, d, f) {
                  return _buildDayCell(d, _events[DateTime.utc(d.year, d.month, d.day)], isToday: true);
                },
                selectedBuilder: (ctx, d, f) {
                  return _buildDayCell(d, _events[DateTime.utc(d.year, d.month, d.day)], isSelected: true);
                },
                outsideBuilder: (ctx, d, f) {
                  return Container(
                    width: MediaQuery.of(context).size.width / 7,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Center(
                        child: Text('${d.day}', style: TextStyle(color: Colors.grey.shade400))),
                  );
                },
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return null;
                  final hasGo = events.contains('go');
                  final hasBack = events.contains('back');
                  return Positioned(
                    bottom: 8,
                    right: 8,
                    child: Row(
                      children: [
                        if(hasGo) Container(
                          width: 8, height: 8, margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                        ),
                        if(hasBack) Container(
                          width: 8, height: 8, margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          // ページ切り替え中や再読み込み中にインジケーターを表示
          if(_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
        ],
      );
    }

    // Stackと更新ボタンはそのまま維持
    return Stack(
      children: [
        body,
        if (_errorMessage == null)
          Positioned(
            top: 7,
            right: 60,
            child: Material(
              color: Colors.white.withOpacity(0.8),
              elevation: 4.0,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isLoading ? null : _initializeAndLoadEvents,
                tooltip: 'カレンダーを更新',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDayCell(DateTime day, List<String>? events,
      {bool isToday = false, bool isSelected = false}) {
    return Container(
      width: MediaQuery.of(context).size.width / 7,
      decoration: BoxDecoration(
        border: Border.all(color: isToday ? Colors.orange : Colors.grey.shade300, width: isToday ? 2 : 1),
        color: isSelected ? Colors.blue.shade100 : null,
      ),
      child: Center(
        child: Text(
          '${day.day}',
          style: TextStyle(fontWeight: isToday ? FontWeight.bold : FontWeight.normal),
        ),
      ),
    );
  }
}
