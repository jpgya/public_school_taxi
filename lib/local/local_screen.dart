import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:numberpicker/numberpicker.dart';

import 'package:school_taxi/student/student.dart';

import '../class.dart';
import '../button.dart';
import '../classTaxi.dart';
import '../localClass.dart' hide RideRecord;
import 'account_local.dart';

class LocalMainPage extends ConsumerStatefulWidget {
  const LocalMainPage({super.key, required this.title ,required this.jititai});

  final String title;
  final String jititai;





  @override
  LocalMainPageState createState() => LocalMainPageState();
}

// SingleTickerProviderStateMixin を追加します
class LocalMainPageState extends ConsumerState<LocalMainPage> with SingleTickerProviderStateMixin {
  String? selectedValue;
  bool showError = false;
  bool _isPriceLocked = true; // 初期状態はロックされていない
  int _priceValue = 0;
  int _monthValue = 0;
  int _yearValue = 0;
  int schoolNumber = 0;

  String? selectedValue1;
  String? selectedValue2;
  String? selectedValue3;
  String? selectedValue4;

  bool showError1=false;
  bool showError2=false;
  bool showError3=false;
  bool showError4=false;

  final TextEditingController _localController = TextEditingController();
  final TextEditingController _schoolController = TextEditingController();
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final TextEditingController _localSchoolController = TextEditingController();



  final TextEditingController _individualDropdownController = TextEditingController();







  List<String> _availableSchoolNames = [];

  // 選択された学校の生徒リスト


  int _totalRegistrationsCount = 0; // 全登録情報数
  int _filteredStudentsCount = 0;   // フィルタリングされた生徒数







  final TextEditingController _dropdownController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _currentUser; // 現在のユーザーを保持する変数



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




  // TabController を宣言します
  late TabController _tabController;

  final List<RideRecord> sampleRecords = List.generate(
    10, // 10件のサンプルデータ
        (index) => RideRecord(
      date: DateTime.now().subtract(Duration(days: index)),
      vehicle: 'MH1', // 車両はMH1のみ
      distance: 20.5 + (index * 2.3),
      passengers: (index % 4) + 1, // 1から4人
    ),
  );

  @override
  void initState() {
    super.initState();
    // TabController を初期化します
    _tabController = TabController(length: 3, vsync: this);

    super.initState();
    // 画面初期化時に現在のユーザーを取得
    _currentUser = _auth.currentUser;

    super.initState();

    _availableSchoolNames.sort();




  }

  @override
  void dispose() {
    // TabController を破棄します
    _tabController.dispose();
    super.dispose();
  }

  void _customAddNewSchool() {
    print("メイン画面: カスタム新規登録アクション！");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('メイン画面：カスタム新規登録が実行されました！')),
    );
    // 実際の処理
  }


  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              icon: const Icon(Icons.account_circle),
              onPressed: _openAccountManagement,
            ),
          ],

          automaticallyImplyLeading: false,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: MediaQuery.of(context).size.width * 0.14),
              FittedBox(fit: BoxFit.scaleDown, child: Text(widget.title, style: TextStyle(color: Colors.white))),
            ],
          ),
          backgroundColor: Colors.orange,
          iconTheme: const IconThemeData(color: Colors.white),
          // AppBar の bottom プロパティに TabBar を設定します
          bottom: TabBar(
            controller: _tabController, // 作成した TabController を指定します
            labelColor: Colors.white, // 選択されているタブのテキスト色
            unselectedLabelColor: Colors.white70, // 選択されていないタブのテキスト色
            indicatorColor: Colors.white, // インジケータの色
            tabs: const [
              Tab(text: '自治体'), // 1つ目のタブ
              Tab(text: '学校'), // 2つ目のタブ
              Tab(text: 'タクシー'), // 3つ目のタブ
            ],
          ),
        ),
        // TabBarView を body に設定し、各タブに対応するコンテンツを表示します
        body: TabBarView(
          controller: _tabController, // AppBar と同じ TabController を指定します
          children: <Widget>[
            // タブ 1 のコンテンツ
            SingleChildScrollView(
              child: Column(
                children: [
                  JititaiTabContent(jititaiName: widget.jititai),
                ],
              ),

            ),
            // タブ 2 のコンテンツ
            SingleChildScrollView(
              child: Column(
                children: [
                  StaticSchoolInfoTabContent(


                  ),


                ],
              ),

            ),


            // タブ 3 のコンテンツ
            SingleChildScrollView(
              child: Column(
                children: [
                  StaticTaxiInfoTabContent(


                  ),


                ],
              ),

            ),
          ],
        ),



      ),
    );
  }
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[700], size: 20),
          SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
