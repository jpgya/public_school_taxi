import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 実際のパスに合わせて修正してください
import 'local_login.dart'; // 自治体/学校職員用の新規登録ページ (LocalRegistrationPageModified が定義されている想定)
import 'local_screen.dart'; // 自治体/学校職員用のログイン後メインページ (LocalMainPage が定義されている想定)

final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class LocalPage extends ConsumerStatefulWidget {
  const LocalPage({super.key, required this.title});
  final String title;

  @override
  LocalPageState createState() => LocalPageState();
}

class LocalPageState extends ConsumerState<LocalPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoggingIn = false;

  static const String _lastLocalEmailKey = 'last_successful_local_email';

  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final String? lastEmail = prefs.getString(_lastLocalEmailKey);
    if (mounted && lastEmail != null) {
      _emailController.text = lastEmail;
    }
  }

  Future<void> _saveEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastLocalEmailKey, _emailController.text);
  }

  Future<void> _loginUser() async {
    if (!mounted) return;
    FocusScope.of(context).unfocus();

    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('メールアドレスとパスワードを入力してください。')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isLoggingIn = true);

    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      print('ログイン成功 (LocalPage): UID ${userCredential.user?.uid}');

      String? fetchedMunicipalityFullName;
      bool isAuthorizedUser = false;

      if (userCredential.user != null) {
        DocumentSnapshot userDoc = await _firestore
            .collection('local_users') // ★★★ 自治体ユーザー情報コレクション ★★★
            .doc(userCredential.user!.uid)
            .get();

        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('municipalityFullName')) {
            fetchedMunicipalityFullName = data['municipalityFullName'] as String?;
            if (fetchedMunicipalityFullName != null && fetchedMunicipalityFullName.isNotEmpty) {
              // 【推奨】ここでさらに 'role' フィールドなどをチェックして認可を強化
              // 例: if (data.containsKey('role') && data['role'] == 'local_staff') {
              // isAuthorizedUser = true;
              // } else { print('適切なロールがありません。'); }
              isAuthorizedUser = true; // 上記ロールチェックを実装しない場合はこのまま
            } else {
              print('UID ${userCredential.user!.uid}: municipalityFullNameが空またはnullです。');
            }
          } else {
            print('UID ${userCredential.user!.uid}: municipalityFullNameフィールドが存在しません。');
          }
        } else {
          print('UID ${userCredential.user!.uid}: local_usersコレクションにドキュメントが見つかりません。');
        }
      }

      if (!isAuthorizedUser || fetchedMunicipalityFullName == null) {
        await _auth.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('このアカウントは自治体職員用として登録されていないか、情報が不足しています。')),
        );
        setState(() => _isLoggingIn = false);
        return;
      }

      await _saveEmail();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => LocalMainPage( // local_screen.dart からインポートされる想定
            title: "管理画面",
            jititai: fetchedMunicipalityFullName!, // nullでないことは上で確認済み
          ),
        ),
      );

    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      print('ログイン FirebaseAuthException (LocalPage): ${e.code} - ${e.message}');
      String message = 'ログインに失敗しました。';
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'メールアドレスまたはパスワードが正しくありません。';
      } else if (e.code == 'invalid-email') {
        message = 'メールアドレスの形式が正しくありません。';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e, s) {
      if (!mounted) return;
      print('ログイン予期せぬエラー (LocalPage): $e\n$s');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('予期せぬエラーが発生しました。')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }
  }

  void _navigateToRegistration() {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocalRegistrationPageModified( // local_login.dart からインポートされる想定
          title: "新規登録",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (mounted) FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(

          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.title, style: const TextStyle(color: Colors.white)),
              SizedBox(width: MediaQuery.of(context).size.width * 0.16)
            ],
          ),
          backgroundColor: Colors.orange,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: 250,
                  child: Image.asset('images/local.jpg', fit: BoxFit.contain), // ★★★ 画像パス確認 ★★★
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailController,
                  focusNode: _emailFocusNode,
                  decoration: const InputDecoration(
                    labelText: 'メールアドレス（ログインID）',
                    hintText: 'admin@example.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) {
                    if (mounted) FocusScope.of(context).requestFocus(_passwordFocusNode);
                  },
                  autofillHints: const [AutofillHints.email],
                  enabled: !_isLoggingIn,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  decoration: const InputDecoration(
                    labelText: 'パスワード',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _loginUser(),
                  autofillHints: const [AutofillHints.password],
                  enabled: !_isLoggingIn,
                ),
                const SizedBox(height: 25),
                if (_isLoggingIn)
                  const Center(child: CircularProgressIndicator())
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                textStyle: const TextStyle(fontSize: 18)),
                            onPressed: _navigateToRegistration,
                            child: const Text("新規登録"),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                textStyle: const TextStyle(fontSize: 18)),
                            onPressed: _loginUser,
                            child: const Text("ログイン"),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
