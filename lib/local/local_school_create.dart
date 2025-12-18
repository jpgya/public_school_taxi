import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NewSchoolCreationPage extends StatefulWidget {
  const NewSchoolCreationPage({Key? key}) : super(key: key);

  @override
  _NewSchoolCreationPageState createState() => _NewSchoolCreationPageState();
}

class _NewSchoolCreationPageState extends State<NewSchoolCreationPage> {
  final _formKey = GlobalKey<FormState>();

  // Firebaseインスタンス
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 各入力フィールド用のコントローラー
  final TextEditingController _schoolNameController = TextEditingController();
  final TextEditingController _invitationCodeController = TextEditingController(); // ★★★ 招待コード用コントローラーを追加
  final TextEditingController _phoneNumberController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _schoolNameController.dispose();
    _invitationCodeController.dispose(); // ★★★ disposeに追加
    _phoneNumberController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  /// ★★★ Firestoreで招待コードが既に存在するかチェックするメソッド ★★★
  Future<bool> _isInvitationCodeDuplicate(String code) async {
    final querySnapshot = await _firestore
        .collection('invitation_codes') // ★ チェック対象コレクションを 'invitation_codes' に
        .where('code', isEqualTo: code)
        .limit(1)
        .get();
    return querySnapshot.docs.isNotEmpty;
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    // ログインユーザーのチェックは必須ではないかもしれないので、一旦コメントアウト
    final User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ログイン情報が無効です。再ログインしてください。'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isLoading = false); // ローディングを解除
      return;
    }
    // ...

    final String schoolName = _schoolNameController.text.trim();
    final String phoneNumber = _phoneNumberController.text.trim();
    final String address = _addressController.text.trim();
    final String invitationCode = _invitationCodeController.text.trim(); // ★ 招待コードを取得

    try {
      // ★★★ 招待コードの重複チェック ★★★
      final bool isDuplicate = await _isInvitationCodeDuplicate(invitationCode);
      if (isDuplicate) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('この招待コードは既に使用されています。別のコードを入力してください。'),
            backgroundColor: Colors.red,
          ),
        );
        // finallyを通ってローディングを解除するために、ここで処理を終了
        return;
      }

      // --- ステップ1: 新しい学校を `schools` コレクションに作成 ---
      final newSchoolRef = _firestore.collection('schools').doc(); // ランダムIDで参照を作成
      await newSchoolRef.set({
        'municipalityId': currentUser.uid, // 必要であれば復活させる
        'name': schoolName,
        'phoneNumber': phoneNumber,
        'address': address,
        'createdAt': Timestamp.now(),
      });

      // --- ステップ2: 招待コードを `invitation_codes` コレクションに作成 ---
      await _firestore.collection('invitation_codes').add({ // .add でランダムIDドキュメントを作成
        'code': invitationCode,
        'schoolId': newSchoolRef.id, // ★ ステップ1で作成した学校のIDを使用
        'createdAt': Timestamp.now(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('学校「$schoolName」が正常に登録されました。'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop(true); // 成功したら前の画面に戻る (trueを渡して更新を通知)
      }
    } catch (e) {
      print('学校登録エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('学校の登録中にエラーが発生しました: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新規学校作成', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.orange,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '新しい学校の情報を入力してください:',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 25),
              TextFormField(
                controller: _schoolNameController,
                decoration: const InputDecoration(
                  labelText: '学校名',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.account_balance),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '学校名を入力してください。';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // ★★★ 招待コードの入力フォームを追加 ★★★
              TextFormField(
                controller: _invitationCodeController,
                decoration: const InputDecoration(
                  labelText: '生徒用の招待コード',
                  hintText: '例: SAKURA_2024',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '生徒用の招待コードを入力してください。';
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
                  final phoneRegExp = RegExp(r'^\d{10,11}$'); // ハイフンなしの10桁か11桁
                  if (!phoneRegExp.hasMatch(value.replaceAll('-', ''))) {
                    return '有効な電話番号の形式で入力してください。';
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
              const SizedBox(height: 35),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('登録する'),
                onPressed: _submitForm,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
