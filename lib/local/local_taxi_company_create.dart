import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // ★★★ Firestoreをインポート

class NewTaxiCreationPage extends StatefulWidget {
  const NewTaxiCreationPage({Key? key}) : super(key: key);

  @override
  _NewTaxiCreationPageState createState() => _NewTaxiCreationPageState();
}

class _NewTaxiCreationPageState extends State<NewTaxiCreationPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // ★★★ Firestoreのインスタンスを作成

  // 各入力フィールド用のコントローラー
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _invitationCodeController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isSaving = false; // ★★★ 保存中のローディング状態を管理



  @override
  void dispose() {
    _companyNameController.dispose();
    _invitationCodeController.dispose();
    _phoneNumberController.dispose();
    _addressController.dispose();
    super.dispose();
  }



  /// ★★★ Firestoreに新しい会社と招待コードを保存するメソッド ★★★
  Future<void> _saveNewCompany() async {
    // 1. フォームのバリデーションを実行
    if (!_formKey.currentState!.validate()) {
      return; // バリデーションエラーがあれば処理を中断
    }

    // ★★★ ユーザーのログイン状態を最初にチェック ★★★
    final User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ログイン情報が無効です。再ログインしてください。'),
          backgroundColor: Colors.red,
        ),
      );
      // ★★★ 処理を中断することを忘れない ★★★
      return;
    }

    setState(() {
      _isSaving = true; // 保存処理を開始
    });

    try {
      // --- ステップ1: 新しい会社を `companys` コレクションに作成 ---
      final newCompanyRef = _firestore.collection('companys').doc();
      final newCompanyData = {
        'name': _companyNameController.text.trim(),
        'phoneNumber': _phoneNumberController.text.trim(),
        'address': _addressController.text.trim(),
        'createdAt': Timestamp.now(),
        'municipalityId': currentUser.uid,
      };
      await newCompanyRef.set(newCompanyData);

      // --- ステップ2: 招待コードを `invitation_codes_drivers` コレクションに作成 ---
      final newInvitationCodeData = {
        'code': _invitationCodeController.text.trim(),
        'companyId': newCompanyRef.id,
        'createdAt': Timestamp.now(),
        // ★★★ currentUserがnullでないことが保証されているので、`!`を付けて安全にUIDを取得 ★★★
        
      };
      await _firestore.collection('invitation_codes_drivers').add(newInvitationCodeData);

      // --- 成功した場合 ---
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('新しい会社と招待コードを登録しました。'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);

    } catch (e) {
      // --- エラーが発生した場合 ---
      debugPrint("Error saving new company: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('登録に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      // --- 処理が完了したら ---
      if (mounted) {
        setState(() {
          _isSaving = false; // 保存処理を終了
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新規タクシー会社作成'),
        backgroundColor: Colors.orange,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '新しい会社の情報を入力してください:',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _companyNameController, // ★ コントローラー名を修正
                decoration: const InputDecoration(
                  labelText: '会社名',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.account_balance),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '会社名を入力してください。';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _invitationCodeController, // ★ コントローラー名を修正
                decoration: const InputDecoration(
                  labelText: '招待コード',
                  hintText: '例: MURA_TAXI_2024',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key_outlined), // アイコンを変更
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'タクシー用の招待コードを入力してください。';
                  }
                  /// ★★★ Firestoreで招待コードが既に存在するかチェックするメソッド ★★★
                  Future<bool> _isInvitationCodeDuplicate(String code) async {
                    final querySnapshot = await _firestore
                        .collection('invitation_codes_drivers')
                        .where('code', isEqualTo: code)
                        .limit(1)
                        .get();
                    return querySnapshot.docs.isNotEmpty; // ドキュメントが1つでも存在すればtrue (重複あり)
                  }

                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneNumberController,
                decoration: const InputDecoration(
                  labelText: '電話番号',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '電話番号を入力してください。';
                  }
                  if (!RegExp(r'^\d{10,11}$').hasMatch(value.replaceAll('-', ''))) {
                    return '有効な電話番号を入力してください。';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: '住所',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '住所を入力してください。';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),
              // ★★★ 保存中のローディング表示に対応したボタン ★★★
              _isSaving
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('登録する'),
                onPressed: _saveNewCompany, // ★★★ 保存メソッドを呼び出し
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
