import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:school_taxi/button.dart';
import 'package:school_taxi/taxiDriver/models/map.dart';
import 'package:school_taxi/taxiDriver/taxi_driver_map.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'account.dart';
import 'models/calendar.dart';





class TaxiDriverMainPage extends ConsumerStatefulWidget {
  const TaxiDriverMainPage({super.key, required this.title});

  final String title;

  @override
  TaxiDriverMainPageState createState() => TaxiDriverMainPageState();
}

class TaxiDriverMainPageState extends ConsumerState<TaxiDriverMainPage> {

  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _currentUser; // 現在のユーザーを保持する変数

  @override
  void initState() {
    super.initState();
    // 画面初期化時に現在のユーザーを取得
    _currentUser = _auth.currentUser;

  }

  void _openAccountManagement() {
    // ここでアカウント管理画面への遷移や、ダイアログ表示などの処理を実装します
    print("アカウント管理ボタンが押されました");
    // 例: スナックバー表示

    // 例: アカウント情報ページに遷移する場合
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AccountPage()), // AccountPage は別途作成
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? userIdFromAuth = _currentUser?.uid;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.green,
          title: Row(
            children: [
              SizedBox(width: MediaQuery.of(context).size.width * 0.15),
              FittedBox(fit: BoxFit.scaleDown, child: Text(widget.title, style: const TextStyle(color: Colors.white)),),
            ],
          ),
          automaticallyImplyLeading: false,
          actions: <Widget>[
            // ★★★ この部分を追加 ★★★
            IconButton(
              icon: const Icon(Icons.account_circle),
              tooltip: 'アカウント管理', // (オプション) 長押しした際に表示されるヒント
              onPressed: _openAccountManagement, // ボタンが押されたときの処理
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: CalendarScreen(userId: userIdFromAuth)),


          ],
        ) // ← カレンダーを表示

      ),
    );
  }
}

