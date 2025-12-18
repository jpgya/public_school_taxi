import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:school_taxi/local/local_taxi_company_create.dart';

import 'local/local_school_create.dart'; // DateFormat を使うために必要

// データモデル (前のステップで定義)
class RideRecord {
  final DateTime date;
  final String vehicle;
  final double distance;
  final int passengers;

  RideRecord({
    required this.date,
    required this.vehicle,
    required this.distance,
    required this.passengers,
  });
}

class ScrollableRideTable extends StatefulWidget {
  final List<RideRecord> records;

  const ScrollableRideTable({Key? key, required this.records}) : super(key: key);

  @override
  _ScrollableRideTableState createState() => _ScrollableRideTableState();
}

class _ScrollableRideTableState extends State<ScrollableRideTable> {
  final DateFormat _dateFormatter = DateFormat('yyyy/MM/dd');
  final double _rowHeight = 50.0; // 各行の高さ (調整可能)
  final int _visibleRows = 5;    // 表示する行数

  // 各列の幅の割合 (TableColumnWidth.fraction) を指定
  final Map<int, TableColumnWidth> _columnWidths = {
    0: FractionColumnWidth(0.25), // 日付
    1: FractionColumnWidth(0.20), // 車両
    2: FractionColumnWidth(0.30), // 運行距離
    3: FractionColumnWidth(0.25), // 乗車人数
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        _buildScrollableBody(),
      ],
    );
  }

  // ヘッダー行を構築
  Widget _buildHeader() {
    return Table(
      columnWidths: _columnWidths,
      border: TableBorder(
        horizontalInside: BorderSide(width: 1, color: Colors.grey.shade300),
        bottom: BorderSide(width: 2, color: Colors.grey.shade600), // ヘッダーの下線を太く
      ),
      children: [
        TableRow(
          children: [
            _buildHeaderCell('日付'),
            _buildHeaderCell('車両'),
            _buildHeaderCell('運行距離'),
            _buildHeaderCell('乗車人数'),
          ],
        ),
      ],
    );
  }

  Widget _buildHeaderCell(String text) {
    return Container(
      height: _rowHeight,
      padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // スクロール可能なデータ行部分を構築
  Widget _buildScrollableBody() {
    if (widget.records.isEmpty) {
      return Container(
        height: _rowHeight * _visibleRows,
        alignment: Alignment.center,
        child: Text('データがありません'),
      );
    }

    return SizedBox(
      height: _rowHeight * _visibleRows, // 表示する行数分の高さを確保
      child: SingleChildScrollView(
        child: Table(
          columnWidths: _columnWidths,
          border: TableBorder.all(width: 1, color: Colors.grey.shade300), // セルごとの罫線
          children: widget.records.map((record) {
            return TableRow(
              children: [
                FittedBox(fit: BoxFit.scaleDown, child: _buildDataCell(_dateFormatter.format(record.date))),
                _buildDataCell(record.vehicle),
                _buildDataCell('${record.distance.toStringAsFixed(1)} km'),
                _buildDataCell('${record.passengers} 人'),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildDataCell(String text) {
    return Container(
      height: _rowHeight,
      padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      alignment: Alignment.center, // データも中央揃えにする場合
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14),
      ),
    );
  }
}







// このファイルの上部にある不要なクラス定義は削除されていると仮定します。
// RideRecord, ScrollableRideTable などは別ファイルに移動されているはずです。

// --- データモデルクラスの定義 ---

class SchoolInfo {
  final String id; // ドキュメントID
  final String name;
  final String phoneNumber;
  final String address;

  SchoolInfo({
    required this.id,
    required this.name,
    this.phoneNumber = "情報なし",
    this.address = "情報なし",
  });

  // FirestoreのドキュメントからSchoolInfoオブジェクトを生成するファクトリコンストラクタ
  factory SchoolInfo.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return SchoolInfo(
      id: doc.id,
      name: data['name'] ?? '名前なし',
      phoneNumber: data['phoneNumber'] ?? '電話番号なし',
      address: data['address'] ?? '住所なし',
    );
  }
}

/// Firestoreの 'Users' コレクションのデータを表すクラス (生徒)
class StudentInfo {
  final String id; // ドキュメントID (UID)
  final String name;
  final String address;

  StudentInfo({
    required this.id,
    required this.name,
    this.address = "情報なし",
  });

  // FirestoreのドキュメントからStudentInfoオブジェクトを生成するファクトリコンストラクタ
  factory StudentInfo.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return StudentInfo(
      id: doc.id,
      name: data['displayName'] ?? '名前なし',
      address: data['Address'] ?? '住所なし', // ★★★ Firestoreのフィールド名が'Address'であることを確認
    );
  }
}

// --- StatefulWidgetの定義 ---

class StaticSchoolInfoTabContent extends StatefulWidget {
  final VoidCallback? onAddPressed;
  final VoidCallback? onAddNewSchoolFromDropdown;
  // final ValueChanged<SchoolInfo?>? onEditPressed; // 編集機能が必要な場合は、型をSchoolInfoに変更して有効化

  const StaticSchoolInfoTabContent({
    Key? key,
    this.onAddPressed,
    this.onAddNewSchoolFromDropdown,
    // this.onEditPressed,
  }) : super(key: key);

  @override
  _StaticSchoolInfoTabContentState createState() =>
      _StaticSchoolInfoTabContentState();
}

// --- Stateクラスの定義 (Firebase連携) ---

class _StaticSchoolInfoTabContentState extends State<StaticSchoolInfoTabContent> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 状態管理用の変数
  List<SchoolInfo> _schools = []; // Firestoreから取得した学校リスト
  SchoolInfo? _selectedSchool; // 選択された学校
  List<StudentInfo> _students = []; // 選択された学校に所属する生徒リスト
  String? _invitationCode;      // ★★★ 招待コードを保持する変数を追加 ★★★
  bool _isLoadingSchools = true;
  bool _isLoadingStudents = false;

  // 「新規作成」アクション用の特別なオブジェクト
  final SchoolInfo _newSchoolAction = SchoolInfo(id: '__NEW__', name: '＋ 新規学校作成');

  @override
  void initState() {
    super.initState();
    _fetchSchools(); // 初期化時に学校リストを取得
  }

  /// Firestoreから学校のリストを取得する
  Future<void> _fetchSchools() async {
    setState(() {
      _isLoadingSchools = true;
      _schools = [];
      _selectedSchool = null;
    });

    try {
      // 1. 現在ログインしている自治体アカウントのユーザー情報を取得
      final User? municipalityUser = FirebaseAuth.instance.currentUser;
      if (municipalityUser == null) {
        throw Exception("自治体アカウントとしてログインしていません。");
      }

      // 2. ログインしているアカウントのUIDが、そのままmunicipalityIdとなる
      final String userMunicipalityId = municipalityUser.uid;

      // 3. 取得した `municipalityId` で schools コレクションを絞り込んで取得
      QuerySnapshot snapshot = await _firestore
          .collection('schools')
          .where('municipalityId', isEqualTo: userMunicipalityId) // ★★★ この条件で絞り込み ★★★
          .orderBy('name')
          .get();

      final schools = snapshot.docs.map((doc) => SchoolInfo.fromFirestore(doc)).toList();

      if (!mounted) return;
      setState(() {
        _schools = schools;
        // 初期選択を設定（もし学校があれば）
        if (_schools.isNotEmpty) {
          _selectedSchool = _schools.first;
          // 生徒と招待コードを同時に取得する
          _fetchDataForSelectedSchool();
        }
      });
    } catch (e) {
      debugPrint("Error fetching schools: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('学校の読み込みに失敗しました: $e')),
      );
    } finally {
      if(mounted) {
        setState(() {
          _isLoadingSchools = false;
        });
      }
    }
  }




  /// ★★★ 指定された学校IDに所属する生徒と招待コードの両方を取得する ★★★
  Future<void> _fetchDataForSelectedSchool() async {
    if (_selectedSchool == null) return;

    // 生徒リストと招待コードの取得を並行して実行
    await Future.wait([
      _fetchStudentsForSchool(_selectedSchool!.id),
      _fetchInvitationCodeForSchool(_selectedSchool!.id),
    ]);
  }

  /// ★★★ 指定された学校IDの招待コードをFirestoreから取得する (新設) ★★★
  Future<void> _fetchInvitationCodeForSchool(String schoolId) async {
    setState(() {
      _invitationCode = null; // いったんクリア
    });
    try {
      final querySnapshot = await _firestore
          .collection('invitation_codes')
          .where('schoolId', isEqualTo: schoolId)
          .limit(1) // 招待コードは学校に1つと仮定
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final data = doc.data();
        if (mounted) {
          setState(() {
            _invitationCode = data['code'] as String?;
          });
        }
      } else {
        // 招待コードが見つからなかった場合
        if(mounted) {
          setState(() {
            _invitationCode = "未設定";
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching invitation code for school $schoolId: $e");
      if(mounted) {
        setState(() {
          _invitationCode = "取得エラー";
        });
      }
    }
  }

  /// 指定された学校IDに所属する生徒のリストをFirestoreから取得する
  Future<void> _fetchStudentsForSchool(String schoolId) async {
    setState(() {
      _isLoadingStudents = true;
      _students = []; // 生徒リストをクリア
    });
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('Users') // ★★★ 生徒情報が保存されているコレクション名を確認
          .where('schoolId', isEqualTo: schoolId) // schoolIdで絞り込み
          .get();
      final students = snapshot.docs.map((doc) => StudentInfo.fromFirestore(doc)).toList();
      setState(() {
        _students = students;
      });
    } catch (e) {
      debugPrint("Error fetching students for school $schoolId: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生徒の読み込みに失敗しました: $e')),
      );
    } finally {
      if(mounted){
        setState(() {
          _isLoadingStudents = false;
        });
      }
    }
  }

  /// UI用のヘルパーウィジェット
  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey[700], size: 20),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ドロップダウンに表示するアイテムのリスト（「+ 新規作成」を含む）
    final List<SchoolInfo> dropdownItems = [_newSchoolAction, ..._schools];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 10),
          if (_isLoadingSchools)
            const Center(child: CircularProgressIndicator())
          else
            DropdownMenu<SchoolInfo>(
              width: MediaQuery.of(context).size.width - 40,
              label: const Text('学校を選択'),
              initialSelection: _selectedSchool,
              // ドロップダウンメニューのエントリを生成
              dropdownMenuEntries: dropdownItems.map((school) {
                return DropdownMenuEntry<SchoolInfo>(
                  value: school,
                  label: school.name,
                  style: school.id == '__NEW__'
                      ? ButtonStyle(
                    textStyle: MaterialStateProperty.all(TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary)),
                  )
                      : null,
                );
              }).toList(),
              // アイテムが選択された時の処理
              onSelected: (SchoolInfo? newValue) {
                if (newValue != null && newValue.id == '__NEW__') {
                  // 「新規作成」が選択された場合
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => const NewSchoolCreationPage(),
                  )).then((result) {
                    // もし作成画面からtrueが返ってきたらリストを更新
                    if(result == true) {
                      _fetchSchools();
                    }
                  });
                } else {
                  // 実際の学校が選択された場合
                  setState(() {
                    _selectedSchool = newValue;
                  });
                  // ★★★ 生徒と招待コードを取得するメソッドを呼び出す ★★★
                  _fetchDataForSelectedSchool();
                }
              },
            ),
          const SizedBox(height: 20),
          // 選択された学校の情報を表示するカード
          if (_selectedSchool != null && _selectedSchool!.id != '__NEW__')
            Card(
              elevation: 3,
              margin: const EdgeInsets.only(bottom: 20.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('選択された学校の情報:',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildInfoRow(context, Icons.account_balance, '学校名:', _selectedSchool!.name),
                    _buildInfoRow(context, Icons.phone, '電話番号:', _selectedSchool!.phoneNumber),
                    _buildInfoRow(context, Icons.location_on, '住所:', _selectedSchool!.address),
                    // ★★★ 招待コードの表示を追加 ★★★
                    _buildInfoRow(
                      context,
                      Icons.vpn_key,
                      '招待コード:',
                      _invitationCode ?? '読み込み中...', // nullの場合はメッセージ表示
                    ),
                  ],
                ),
              ),
            )
          else if (!_isLoadingSchools)
            Padding(
              padding: const EdgeInsets.only(bottom: 20.0, top: 10.0),
              child: Text("学校を選択してください。", style: Theme.of(context).textTheme.bodyLarge),
            ),
          const Divider(thickness: 1.5, height: 40),

          // 選択された学校の生徒一覧
          if (_selectedSchool != null && _selectedSchool!.id != '__NEW__')
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${_selectedSchool?.name ?? "学校"}の生徒一覧 (${_students.length}名):',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (_isLoadingStudents)
                  const Center(child: CircularProgressIndicator())
                else if (_students.isNotEmpty)
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _students.length,
                    itemBuilder: (context, index) {
                      final student = _students[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6.0),
                        child: ListTile(
                          leading: CircleAvatar(
                              child: Icon(Icons.person, color: Colors.black)),
                          title: Text(student.name),
                          subtitle: Text("住所: ${student.address}"),
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${student.name} さんがタップされました。')),
                            );
                          },
                        ),
                      );
                    },
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.0),
                    child: Center(child: Text("この学校には登録されている生徒がいません。")),
                  )
              ],
            )
          else if (!_isLoadingSchools)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10.0),
              child: Text("まず学校を選択してください。"),
            ),
        ],
      ),
    );
  }
}



