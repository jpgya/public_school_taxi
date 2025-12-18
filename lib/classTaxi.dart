import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // ★★★ Firestoreパッケージをインポート
import 'local/local_taxi_company_create.dart';

// --- データモデルクラスの定義 ---

/// Firestoreの 'companys' コレクションのデータを表すクラス
class CompanyInfo {
  final String id; // ドキュメントID
  final String name;
  final String phoneNumber; // ★★★ 電話番号フィールドを追加
  final String address;

  CompanyInfo({
    required this.id,
    required this.name,
    this.phoneNumber = "情報なし", // ★★★ コンストラクタに追加
    this.address = "情報なし",
  });

  // FirestoreのドキュメントからCompanyInfoオブジェクトを生成するファクトリコンストラクタ
  factory CompanyInfo.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return CompanyInfo(
      id: doc.id,
      name: data['name'] ?? '名前なし',
      phoneNumber: data['phoneNumber'] ?? '電話番号なし', // ★★★ Firestoreから読み込み
      address: data['address'] ?? '住所なし',
    );
  }
}

/// Firestoreの 'drivers' コレクションのデータを表すクラス
class DriverInfo {
  final String id; // ドキュメントID (UID)
  final String displayName;
  final String email; // 必要に応じて
  final int? maxNum;


  DriverInfo({
    required this.id,
    required this.displayName,
    this.email = "情報なし",
    this.maxNum,
  });

  // FirestoreのドキュメントからDriverInfoオブジェクトを生成するファクトリコンストラクタ
  factory DriverInfo.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return DriverInfo(
      id: doc.id,
      displayName: data['displayName'] ?? '名前なし',
      email: data['email'] ?? 'メールアドレスなし',
      maxNum: data['maxNum'] as int?,
    );
  }
}

// --- StatefulWidgetの定義 ---

class StaticTaxiInfoTabContent extends StatefulWidget {
  final VoidCallback? onAddPressed;
  final VoidCallback? onAddNewSchoolFromDropdown;

  const StaticTaxiInfoTabContent({
    Key? key,
    this.onAddPressed,
    this.onAddNewSchoolFromDropdown,
  }) : super(key: key);

  @override
  _StaticTaxiInfoTabContentState createState() =>
      _StaticTaxiInfoTabContentState();
}

// --- Stateクラスの定義 (Firebase連携) ---

class _StaticTaxiInfoTabContentState extends State<StaticTaxiInfoTabContent> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 状態管理用の変数
  List<CompanyInfo> _companies = []; // Firestoreから取得した会社リスト
  CompanyInfo? _selectedCompany; // 選択された会社
  List<DriverInfo> _drivers = []; // 選択された会社に所属するドライバーリスト
  String? _invitationCode; // ★★★ 招待コードを保持する変数を追加
  bool _isLoadingCompanies = true;
  bool _isLoadingDrivers = false;

  // 「新規作成」アクション用の特別なオブジェクト
  final CompanyInfo _newCompanyAction = CompanyInfo(id: '__NEW__', name: '＋ 新規タクシー会社作成');

  @override
  void initState() {
    super.initState();
    _fetchCompanies(); // 初期化時に会社リストを取得
  }

  /// Firestoreからタクシー会社のリストを取得する
  Future<void> _fetchCompanies() async {
    final User? municipalityUser = FirebaseAuth.instance.currentUser;
    if (municipalityUser == null) {
      throw Exception("自治体アカウントとしてログインしていません。");
    }
    final String userMunicipalityId = municipalityUser.uid;
    setState(() {
      _isLoadingCompanies = true;
    });
    try {
      QuerySnapshot snapshot = await _firestore.collection('companys') .where('municipalityId', isEqualTo: userMunicipalityId).orderBy('name').get();
      // ドキュメントをCompanyInfoオブジェクトのリストに変換
      final companies = snapshot.docs.map((doc) => CompanyInfo.fromFirestore(doc)).toList();
      setState(() {
        _companies = companies;
        // 初期選択を設定（もし会社があれば）
        if (_companies.isNotEmpty) {
          _selectedCompany = _companies.first;
          _fetchDataForSelectedCompany(); // ★★★ 関連データをまとめて取得
        }
      });
    } catch (e) {
      debugPrint("Error fetching companies: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('会社の読み込みに失敗しました: $e')),
      );
    } finally {
      if(mounted) {
        setState(() {
          _isLoadingCompanies = false;
        });
      }
    }
  }

  /// ★★★ 選択された会社の関連データ（ドライバーと招待コード）をまとめて取得 ★★★
  Future<void> _fetchDataForSelectedCompany() async {
    if (_selectedCompany == null) return;
    await Future.wait([
      _fetchDriversForCompany(_selectedCompany!.id),
      _fetchInvitationCodeForCompany(_selectedCompany!.id),
    ]);
  }

  /// ★★★ 指定された会社IDの招待コードをFirestoreから取得する (新設) ★★★
  Future<void> _fetchInvitationCodeForCompany(String companyId) async {


    setState(() {
      _invitationCode = null; // いったんクリア
    });
    try {
      // 'invitation_codes_drivers'コレクションを'companyId'で絞り込む
      final querySnapshot = await _firestore
          .collection('invitation_codes_drivers')
          .where('companyId', isEqualTo: companyId)
          .limit(1) // 招待コードは会社に1つと想定
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        // 見つかったドキュメントから'code'フィールドを取得
        final doc = querySnapshot.docs.first;
        if (mounted) {
          setState(() {
            _invitationCode = doc.data()['code'] as String?;
          });
        }
      } else {
        // 招待コードが見つからなかった場合
        if (mounted) {
          setState(() {
            _invitationCode = '未設定';
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching invitation code for company $companyId: $e");
      if (mounted) {
        setState(() {
          _invitationCode = '取得エラー';
        });
      }
    }
  }


  /// 指定された会社IDに所属するドライバーのリストをFirestoreから取得する
  Future<void> _fetchDriversForCompany(String companyId) async {

    setState(() {
      _isLoadingDrivers = true;
      _drivers = []; // ドライバーリストをクリア
    });
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('drivers')
          .where('companyId', isEqualTo: companyId) // ★★★ この条件で絞り込み ★★
          .get();
      final drivers = snapshot.docs.map((doc) => DriverInfo.fromFirestore(doc)).toList();
      if(mounted){
        setState(() {
          _drivers = drivers;
        });
      }
    } catch (e) {
      debugPrint("Error fetching drivers for company $companyId: $e");
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ドライバーの読み込みに失敗しました: $e')),
      );
    } finally {
      if(mounted) {
        setState(() {
          _isLoadingDrivers = false;
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
    final List<CompanyInfo> dropdownItems = [_newCompanyAction, ..._companies];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 10),
          if (_isLoadingCompanies)
            const Center(child: CircularProgressIndicator())
          else
            DropdownMenu<CompanyInfo>(
              width: MediaQuery.of(context).size.width - 40,
              label: const Text('タクシー会社を選択'),
              initialSelection: _selectedCompany,
              // ドロップダウンメニューのエントリを生成
              dropdownMenuEntries: dropdownItems.map((company) {
                return DropdownMenuEntry<CompanyInfo>(
                  value: company,
                  label: company.name,
                  style: company.id == '__NEW__'
                      ? ButtonStyle(
                    textStyle: MaterialStateProperty.all(TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary)),
                  )
                      : null,
                );
              }).toList(),
              // アイテムが選択された時の処理
              onSelected: (CompanyInfo? newValue) {
                if (newValue != null && newValue.id == '__NEW__') {
                  // 「新規作成」が選択された場合
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => const NewTaxiCreationPage(),
                  )).then((result) {
                    if (result == true) {
                      _fetchCompanies();
                    }
                  });
                } else {
                  // 実際の会社が選択された場合
                  setState(() {
                    _selectedCompany = newValue;
                  });
                  if (_selectedCompany != null) {
                    _fetchDataForSelectedCompany(); // ★★★ 関連データをまとめて取得
                  }
                }
              },
            ),
          const SizedBox(height: 20),
          // 選択された会社の情報を表示するカード
          if (_selectedCompany != null && _selectedCompany!.id != '__NEW__')
            Card(
              elevation: 3,
              margin: const EdgeInsets.only(bottom: 20.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('選択されたタクシー会社の情報:',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildInfoRow(context, Icons.account_balance, '会社名:', _selectedCompany!.name),
                    _buildInfoRow(context, Icons.phone, '電話番号:', _selectedCompany!.phoneNumber), // ★★★ 電話番号表示を追加
                    _buildInfoRow(context, Icons.location_on, '住所:', _selectedCompany!.address),
                    _buildInfoRow(context, Icons.vpn_key, '招待コード:', _invitationCode ?? "読み込み中..."), // ★★★ 招待コード表示を追加
                  ],
                ),
              ),
            )
          else if (!_isLoadingCompanies)
            Padding(
              padding: const EdgeInsets.only(bottom: 20.0, top: 10.0),
              child: Text("タクシー会社を選択してください。", style: Theme.of(context).textTheme.bodyLarge),
            ),
          const Divider(thickness: 1.5, height: 40),

          // 選択された会社のドライバー一覧
          if (_selectedCompany != null && _selectedCompany!.id != '__NEW__')
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${_selectedCompany?.name ?? "会社"}の車両 (${_drivers.length}台):',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (_isLoadingDrivers)
                  const Center(child: CircularProgressIndicator())
                else if (_drivers.isNotEmpty)
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _drivers.length,
                    itemBuilder: (context, index) {
                      final driver = _drivers[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6.0),
                        child: ListTile(
                          leading: const Icon(Icons.local_taxi_outlined), // アイコンを変更
                          title: Text("ナンバープレート: ${driver.displayName}"),
                          subtitle: Text(
                              "最大乗車人数: ${driver.maxNum ?? '未設定'}名"),
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${driver.displayName} がタップされました。')),
                            );
                          },
                        ),
                      );
                    },
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.0),
                    child: Center(child: Text("この会社には登録されている車両がありません。")),
                  )
              ],
            )
          else if (!_isLoadingCompanies)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10.0),
              child: Text("まず会社を選択してください。"),
            ),
        ],
      ),
    );
  }
}
