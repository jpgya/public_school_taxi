import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_taxi/student/screens/calendar_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../button.dart';
import 'account_st.dart';
import 'models/map.dart';

class StudentReservePage extends ConsumerStatefulWidget {
  const StudentReservePage({super.key, required this.title});

  final String title;

  @override
  StudentReservePageState createState() => StudentReservePageState();
}

class StudentReservePageState extends ConsumerState<StudentReservePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _currentUser;
  String? _driverIdForCurrentReservation;
  bool _isLoadingDriverInfo = true; // 初期状態はtrue（ログインチェックとデータ取得のため）
  bool _isLoggedIn = false; // ★★★ ログイン状態を保持するフラグ ★★★

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    _isLoggedIn = (_currentUser != null); // ★★★ initStateでログイン状態をセット ★★★

    if (_isLoggedIn) {
      _loadDriverIdForCurrentReservation();
    } else {
      // ログインしていない場合は、ローディングを終了し、ドライバーIDはnullのまま
      debugPrint("ユーザーはログインしていません。");
      if (mounted) {
        setState(() {
          _isLoadingDriverInfo = false;
        });
      }
    }
  }

  Future<void> _loadDriverIdForCurrentReservation() async {
    if (!mounted) return;
    // ログイン状態は initState でチェック済みなので、ここでは _currentUser が null でない前提
    // ただし、念のため再度チェックしても良い
    if (_currentUser == null) {
      debugPrint("_loadDriverIdForCurrentReservation: currentUser is null. Should not happen if _isLoggedIn is true.");
      if (mounted) setState(() => _isLoadingDriverInfo = false);
      return;
    }

    // setState(() => _isLoadingDriverInfo = true); // initStateで既にセットされているか、ログインしていない場合は呼ばれない

    try {
      QuerySnapshot reservationSnapshot = await _firestore
          .collection('reservations')
          .where('userId', isEqualTo: _currentUser!.uid)
          .where('status', whereIn: ['assigned', 'ongoing', 'confirmed'])
          .orderBy('pickUpOrder', descending: true)
          .limit(1)
          .get();

      if (!mounted) return;

      if (reservationSnapshot.docs.isNotEmpty) {
        final reservationData = reservationSnapshot.docs.first.data() as Map<String, dynamic>;
        _driverIdForCurrentReservation = reservationData['assignedDriverId'] as String?;
        if (_driverIdForCurrentReservation == null || _driverIdForCurrentReservation!.isEmpty) {
          debugPrint("現在の予約にタクシーが割り当てられていません。");
          _driverIdForCurrentReservation = null;
        } else {
          debugPrint("取得したタクシーID: $_driverIdForCurrentReservation");
        }
      } else {
        debugPrint("有効な現在の予約が見つかりません。");
        _driverIdForCurrentReservation = null;
      }
    } catch (e) {
      debugPrint("タクシーIDの初期読み込みエラー: $e");
      _driverIdForCurrentReservation = null;
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDriverInfo = false;
        });
      }
    }
  }

  void _openAccountManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AccountPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? userIdFromAuth = _currentUser?.uid; // CalendarScreen に渡すため

    Widget routeButtonWidget; // ★★★ ボタンウィジェットを格納する変数 ★★★

    if (_isLoadingDriverInfo) { // ★★★ ログイン済みで、ドライバー情報読み込み中の場合 ★★★
      routeButtonWidget = const CircularProgressIndicator();
    } else if (_driverIdForCurrentReservation != null && _driverIdForCurrentReservation!.isNotEmpty) { // ★★★ ドライバーIDが見つかった場合 ★★★
      routeButtonWidget = NavigateButton(
        title: 'マップで確認',
        next: RouteTrackingMapScreen(routeDocId: _driverIdForCurrentReservation!, selectedDate: '', ),
        buttonColor: Colors.green, textColor: Colors.white,
      );
    } else { // ★★★ ログイン済みだが、ドライバーIDが見つからないか、空の場合 ★★★
      routeButtonWidget = Tooltip(
        message: "現在追跡可能なタクシーはありません。",
        child: NavigateButton(
          title: 'マップで確認',

          buttonColor: Colors.grey,
          textColor: Colors.white70,
          next: StudentReservePage(title: widget.title),

        ),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue,
          actions: [
            IconButton(
              icon: const Icon(Icons.account_circle),
              onPressed: _openAccountManagement,
            ),
          ],
          automaticallyImplyLeading: false,
          toolbarHeight: 60,
          title: Center(
            child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  children: [
                    SizedBox(width: MediaQuery.of(context).size.width * 0.15),
                    Center(child: Text(widget.title, style: const TextStyle(fontSize: 30, color: Colors.white,fontFamily: "Noto Sans JP",))),
                  ],
                )
            ),
          ),
        ),
        body: Column(
          children: [
            // このボタンウィジェット用のコンテナを追加

            const Divider(height: 1, thickness: 1),
            // CalendarScreenが残りのスペースをすべて使用するようにExpandedでラップ
            const Expanded(
              child: CalendarScreen(),
            ),
          ],
        ),
      ),
    );
  }
}

