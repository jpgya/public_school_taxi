import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
// dropdown_search と Municipality, Schoolクラスのインポートは不要

import 'taxi_driver_login.dart'; // ドライバー用の新規登録ページ
import 'taxi_driver_screen.dart'; // ドライバー用のメイン画面

// Firestoreのインスタンス
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class TaxiDriverPage extends ConsumerStatefulWidget {
  const TaxiDriverPage({super.key, required this.title});
  final String title;
  @override
  TaxiDriverPageState createState() => TaxiDriverPageState();
}

class TaxiDriverPageState extends ConsumerState<TaxiDriverPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // StudentPage にはないが、ログイン処理中の状態を示すフラグ
  bool _isLoading = false;

  static const String _lastEmailKey = 'last_successful_taxi_driver_email'; // キーを明確化

  // フォーカスノードの定義
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadLastEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadLastEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final String? lastEmail = prefs.getString(_lastEmailKey);
    if (lastEmail != null && mounted) {
      setState(() {
        _emailController.text = lastEmail;
      });
    }
  }

  Future<void> _saveLastEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastEmailKey, email);
  }

  Future<void> _loginDriver() async { // StudentPageの_loginUserに相当
    FocusScope.of(context).unfocus(); // ログイン処理前にフォーカスを外す

    if (_isLoading) return; // 処理中の多重実行を防ぐ

    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('メールアドレスとパスワードを入力してください。')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      print('タクシーログイン成功: ${userCredential.user?.uid}');
      await _saveLastEmail(email);

      // --- ドライバー情報の検証 (StudentPageにはない重要なステップ) ---
      // Firestoreからドライバーの情報を取得し、アカウントの種別や有効性を確認
      DocumentSnapshot driverDoc = await _firestore
          .collection('drivers') // Firestoreのドライバーコレクション名
          .doc(userCredential.user!.uid)
          .get();

      if (!driverDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('タクシーアカウント情報が見つかりません。')),
          );
        }
        await _auth.signOut(); // 認証情報をクリア
        setState(() => _isLoading = false);
        return;
      }
      // final driverData = driverDoc.data() as Map<String, dynamic>?;
      // final bool isActive = driverData?['isActive'] as bool? ?? true; // 例: アカウント有効フラグ
      // final String? role = driverData?['role'] as String?; // 例: 役割
      //
      // if (role != 'driver' || !isActive) {
      //   if (mounted) {
      //     ScaffoldMessenger.of(context).showSnackBar(
      //       const SnackBar(content: Text('このアカウントは使用できません。管理者に確認してください。')),
      //     );
      //   }
      //   await _auth.signOut();
      //   setState(() => _isLoading = false);
      //   return;
      // }
      // --- ドライバー情報の検証ここまで ---

      if (mounted) {
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) => TaxiDriverMainPage(title: "ドライバー専用画面"))); // 遷移先を変更
      }
    } on FirebaseAuthException catch (e) {
      String message = 'ログインに失敗しました。';
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'メールアドレスまたはパスワードが正しくありません。';
      } else if (e.code == 'invalid-email') {
        message = 'メールアドレスの形式が正しくありません。';
      } else if (e.code == 'user-disabled') {
        message = 'このアカウントは無効化されています。';
      }
      print('ログインエラー: ${e.code} ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      print('予期せぬエラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('予期せぬエラーが発生しました。')),
        );
      }
    } finally {
      if(mounted){
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToRegistration() {
    FocusScope.of(context).unfocus(); // 新規登録処理前にフォーカスを外す
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TaxiDriverLoginPage( // 遷移先を変更
          title: "新規登録",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector( // 画面全体を GestureDetector でラップ
      onTap: () {
        FocusScope.of(context).unfocus(); // キーボード以外の場所をタップしたらフォーカスを外してキーボードを閉じる
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true, // trueでキーボード表示時にUIが上にスライド
        appBar: AppBar(

          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(widget.title, style: const TextStyle(color: Colors.white)),
              SizedBox(width: MediaQuery.of(context).size.width * 0.16)
            ],
          ),
          backgroundColor: Colors.green, // ドライバー向けの色に変更 (例:緑系)
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea( // SafeArea で body をラップ
          child: SingleChildScrollView( // コンテンツが画面を超える場合にスクロール可能にする
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start, // 上寄せ
                mainAxisSize: MainAxisSize.min, // 子要素の高さに合わせる
                crossAxisAlignment: CrossAxisAlignment.stretch, // 子要素を水平方向に広げる
                children: <Widget>[
                  SizedBox(
                    // 画像の高さを画面の高さに基づいて調整 (StudentPageより少し小さめも検討)
                    height: MediaQuery.of(context).size.height * 0.3,
                    child: Image.asset(
                      'images/taxi_driver.jpg', // ドライバー用の画像に変更
                      fit: BoxFit.contain, // アスペクト比を保ちつつ収める
                      errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.local_taxi, size: 60, color: Colors.grey, semanticLabel: "Taxi Driver Image Placeholder",)),
                    ),
                  ),
                  const SizedBox(height: 24), // StudentPageより少し間隔を広げる

                  TextField(
                    controller: _emailController,
                    focusNode: _emailFocusNode,
                    decoration: const InputDecoration(
                      labelText: 'メールアドレス（ログインID）',
                      hintText: 'driver@example.com', // ヒントテキストを調整
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) {
                      FocusScope.of(context).requestFocus(_passwordFocusNode);
                    },
                    autofillHints: const [AutofillHints.email, AutofillHints.username],
                    enabled: !_isLoading, // ローディング中は無効化
                  ),
                  const SizedBox(height: 12), // StudentPageより少し間隔を広げる

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
                    onSubmitted: (_) {
                      _loginDriver();
                    },
                    autofillHints: const [AutofillHints.password],
                    enabled: !_isLoading, // ローディング中は無効化
                  ),
                  const SizedBox(height: 28), // StudentPageより少し間隔を広げる

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      SizedBox(
                        height: 50,
                        width: MediaQuery.of(context).size.width * 0.40,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red, // 新規登録ボタンの色を変更 (例: オレンジ)
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), // フォントサイズ調整
                          onPressed: _isLoading ? null : _navigateToRegistration, // ローディング中は無効化
                          child: const Text("新規登録"),
                        ),
                      ),
                      SizedBox(
                        height: 50,
                        width: MediaQuery.of(context).size.width * 0.40,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green, // ログインボタンの色をAppBarと合わせる (例: 緑系)
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), // フォントサイズ調整
                          onPressed: _isLoading ? null : _loginDriver, // ローディング中は無効化
                          child: _isLoading
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                          )
                              : const Text("ログイン"),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30), // 下部の余白
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
