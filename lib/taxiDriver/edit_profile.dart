import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({Key? key}) : super(key: key);

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  User? _currentUser;
  late TextEditingController _displayNameController;
  late TextEditingController _maxNumController;
  // ★★★ Firestoreから編集したい他のフィールド用のコントローラーを追加 ★★★
  // 例: late TextEditingController _phoneNumberController;

  bool _isLoading = true;
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    _displayNameController = TextEditingController(text: _currentUser?.displayName ?? '');
    _maxNumController = TextEditingController();
    // ★★★ 他のフィールドの初期化 ★★★
    // _phoneNumberController = TextEditingController();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _maxNumController.dispose();
    // ★★★ 他のコントローラーをdispose ★★★
    // _phoneNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    if (_currentUser == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "ユーザーがログインしていません。";
        });
      }
      return;
    }

    try {
      DocumentSnapshot userDoc = await _firestore
          .collection('drivers') // ★★★★★ Firestoreの「ドライバー」コレクション名 ★★★★★
          .doc(_currentUser!.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          // Firebase AuthのdisplayNameが空の場合、Firestoreから取得するフォールバック
          if (_displayNameController.text.isEmpty && data.containsKey('displayName')) {
            _displayNameController.text = data['displayName'] as String? ?? '';
          }
          if (data.containsKey('maxNum')) {
            // intをStringに変換して設定
            _maxNumController.text = (data['maxNum'] as num?)?.toString() ?? '';
          }
          // ★★★ Firestoreから他のフィールドをロードしてコントローラーに設定 ★★★
          // 例:
          // if (data.containsKey('phoneNumber')) {
          //   _phoneNumberController.text = data['phoneNumber'] as String? ?? '';
          // }
        }
      }
    } catch (e) {
      debugPrint("Error loading user profile: $e");
      if (mounted) {
        _errorMessage = "プロファイル情報の読み込みに失敗しました。";
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ユーザーがログインしていません。')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      // 1. Firebase Authenticationの表示名を更新
      if (_currentUser!.displayName != _displayNameController.text.trim()) {
        await _currentUser!.updateDisplayName(_displayNameController.text.trim());
      }

      // 2. Firestoreのユーザー情報を更新
      Map<String, dynamic> dataToUpdate = {
        'displayName': _displayNameController.text.trim(),
        'maxNum': int.tryParse(_maxNumController.text.trim()) ?? 0,
        // ★★★ Firestoreに保存する他のフィールドを追加 ★★★
        // 例: 'phoneNumber': _phoneNumberController.text.trim(),
        'updatedAt': Timestamp.now(), // 更新日時
      };

      await _firestore
          .collection('drivers') // ★★★★★ Firestoreの「ドライバー」コレクション名 ★★★★★
          .doc(_currentUser!.uid)
          .update(dataToUpdate);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('プロフィールを更新しました。'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop(); // 更新後、アカウントページに戻る
      }
    } on FirebaseAuthException catch (e) {
      debugPrint("FirebaseAuthException during profile save: ${e.code} - ${e.message}");
      if (mounted) {
        _errorMessage = "表示名の更新に失敗しました: ${e.message}";
      }
    } catch (e) {
      debugPrint("Error saving profile: $e");
      if (mounted) {
        _errorMessage = "プロフィールの保存中にエラーが発生しました。";
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(

        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(fit: BoxFit.scaleDown,child: Text('アカウント - 編集', style: const TextStyle(color: Colors.white))),
            SizedBox(width: MediaQuery.of(context).size.width * 0.16)
          ],
        ),
        backgroundColor: Colors.green,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && !_isSaving // 保存中のエラーはフォーム下に表示するのでここでは表示しない
          ? Center(child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 16), textAlign: TextAlign.center),
      ))
          : _currentUser == null
          ? const Center(child: Text('ユーザー情報がありません。編集できません。'))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '情報を編集して保存してください。',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 25),

              // 表示名
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'ナンバープレート',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.local_taxi_sharp),
                ),
                keyboardType: TextInputType.name,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '名前を入力してください。';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _maxNumController,
                decoration: const InputDecoration(
                  labelText: '最大乗車可能人数', // ラベルを変更
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.group_outlined), // アイコンを変更
                ),
                keyboardType: TextInputType.number, // キーボードを数値入力に変更
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '最大乗車可能人数を入力してください。';
                  }
                  if (int.tryParse(value) == null) {
                    return '有効な数値を入力してください。';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ★★★ Firestoreから編集したい他のフィールド用のTextFormFieldを追加 ★★★
              // 例: 電話番号
              // TextFormField(
              //   controller: _phoneNumberController,
              //   decoration: const InputDecoration(
              //     labelText: '電話番号',
              //     border: OutlineInputBorder(),
              //     prefixIcon: Icon(Icons.phone_outlined),
              //   ),
              //   keyboardType: TextInputType.phone,
              //   validator: (value) {
              //     // 必要に応じてバリデーション
              //     return null;
              //   },
              // ),
              // const SizedBox(height: 20),


              // エラーメッセージ表示 (保存時)
              if (_errorMessage != null && _isSaving)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0, top: 8.0),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),

              const SizedBox(height: 30),
              _isSaving
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                icon: const Icon(Icons.save_alt_outlined),
                label: const Text('保存する'),
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
