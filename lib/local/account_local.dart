import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:school_taxi/main.dart';
import 'package:school_taxi/taxiDriver/taxi_driver_login.dart';

import 'edit_profile_local.dart';

// import 'package:school_taxi/auth/login_page.dart'; // ログアウト後の遷移先ページ (適宜変更)

class AccountPage extends StatefulWidget {
  const AccountPage({Key? key}) : super(key: key);

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _currentUser;
  Map<String, dynamic>? _userData; // Firestoreからの追加ユーザーデータ
  String? _schoolName; // Firestoreから取得した会社名
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _currentUser = _auth.currentUser;
    if (_currentUser == null) {
      // ログインしていない場合はログインページなどにリダイレクトするなどの処理も考えられる
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "ユーザーがログインしていません。";
        });
      }
      return;
    }

    try {
      // Firestoreから追加情報を取得 (例: drivers コレクション)
      DocumentSnapshot userDoc = await _firestore
          .collection('local_users') // ★★★★★ Firestoreの「ドライバー」コレクション名に合わせてください ★★★★★
          .doc(_currentUser!.uid)
          .get();

      if (userDoc.exists) {
        _userData = userDoc.data() as Map<String, dynamic>?;
        if (_userData != null && _userData!.containsKey('municipalityFullName')) {
          final String? municipalityName = _userData!['municipalityFullName'] as String?;
          if (municipalityName != null && municipalityName.isNotEmpty) {

            if (userDoc.exists) {
              _schoolName = (userDoc.data() as Map<String, dynamic>?)?['name'] as String?; // ★★★★★ 会社名フィールドを確認 ★★★★★
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error loading user data: $e");
      if (mounted) {
        _errorMessage = "ユーザー情報の読み込みに失敗しました。";
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
      // ログアウト後、ログインページなどに遷移
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const MyApp()), // LoginPageは実際のログインページのクラス名に置き換える
              (Route<dynamic> route) => false, // 現在のルートスタックをすべて削除
        );
      }
    } catch (e) {
      debugPrint("Error signing out: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ログアウトに失敗しました: ${e.toString()}')),
        );
      }
    }
  }

  void _navigateToEditProfile() {

    // ScaffoldMessenger.of(context).showSnackBar(
    //   const SnackBar(content: Text('プロフィール編集機能は未実装です。')),
    // );
    Navigator.push(context, MaterialPageRoute(builder: (context) => EditProfilePage()));
  }

  void _changePassword() {

    if (_currentUser?.email != null) {
      _auth.sendPasswordResetEmail(email: _currentUser!.email!)
          .then((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_currentUser!.email} にパスワード再設定メールを送信しました。')),
        );
      }).catchError((error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('パスワード再設定メールの送信に失敗しました: $error')),
        );
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('メールアドレスが登録されていません。')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(

        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('アカウント情報', style: const TextStyle(color: Colors.white)),
            SizedBox(width: MediaQuery.of(context).size.width * 0.16)
          ],
        ),
        backgroundColor: Colors.orange,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 16), textAlign: TextAlign.center),
      ))
          : _currentUser == null
          ? const Center(child: Text('ユーザー情報がありません。'))
          : RefreshIndicator( // ★★★ 引っ張って更新機能を追加 ★★★
        onRefresh: _loadUserData,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: <Widget>[
            _buildUserInfoSection(),
            const SizedBox(height: 24),
            _buildActionsSection(),
            const SizedBox(height: 32),
            Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('ログアウト'),
                onPressed: () => _showLogoutConfirmDialog(context), // ★★★ 確認ダイアログを挟む ★★★
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfoSection() {
    return Card(
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '登録情報',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent),
            ),
            const Divider(height: 24),
            _buildInfoRow(Icons.person_outline, '名前:', _currentUser?.displayName ?? '未設定'),
            _buildInfoRow(Icons.email_outlined, 'メールアドレス:', _currentUser?.email ?? '未登録'),
            if (_schoolName != null)
              _buildInfoRow(Icons.business_outlined, '学校名:', _schoolName!),
            // 必要に応じてFirestoreから取得した他の情報を表示
            // if (_userData != null && _userData!['someOtherField'] != null)
            //   _buildInfoRow(Icons.info_outline, 'その他情報:', _userData!['someOtherField'].toString()),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.grey[700], size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[800]),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(fontSize: 15, color: Colors.grey[800]),
              softWrap: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsSection() {
    return Card(
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _buildActionItem(
            icon: Icons.edit_outlined,
            title: 'プロフィールを編集',
            onTap: _navigateToEditProfile,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _buildActionItem(
            icon: Icons.lock_outline,
            title: 'パスワードを変更',
            onTap: _changePassword,
          ),
          // 必要に応じて他のアクション項目を追加
        ],
      ),
    );
  }

  Widget _buildActionItem({required IconData icon, required String title, required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.blueAccent),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
    );
  }

  // ★★★ ログアウト確認ダイアログ ★★★
  Future<void> _showLogoutConfirmDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // ユーザーがダイアログ外をタップしても閉じない
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('ログアウト確認'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('本当にログアウトしますか？'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('キャンセル'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // ダイアログを閉じる
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('ログアウトする', style: TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // ダイアログを閉じる
                _signOut(); // ログアウト処理を実行
              },
            ),
          ],
        );
      },
    );
  }
}

// ★★★ ログアウト後の遷移先ページの仮実装 (実際のログインページに置き換えてください) ★★★


