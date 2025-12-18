import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:school_taxi/student/student_registration.dart';
import 'package:school_taxi/student/student_reserve.dart';

final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class Municipality {
  final String id;
  final String name;
  Municipality({required this.id, required this.name});

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Municipality && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class School {
  final String id;
  final String name;
  final String municipalityId;
  School({required this.id, required this.name, required this.municipalityId});

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is School && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class StudentPage extends ConsumerStatefulWidget {
  const StudentPage({super.key, required this.title});
  final String title;
  @override
  StudentPageState createState() => StudentPageState();
}

class StudentPageState extends ConsumerState<StudentPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<Municipality> municipalities = [];
  List<School> allSchools = [];
  List<School> filteredSchools = [];

  Municipality? selectedMunicipality;
  School? selectedSchool;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool isLoadingMunicipalities = true;
  bool isLoadingSchools = true;

  static const String _lastEmailKey = 'last_successful_email';

  // フォーカスノードの定義
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadLastEmail();
    _fetchMunicipalities();
    _fetchAllSchools();
  }

  @override
  void dispose() {
    // TextEditingController と FocusNode を dispose
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

  Future<void> _fetchMunicipalities() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection('municipalities').get();
      if (mounted) {
        setState(() {
          municipalities = snapshot.docs
              .map((doc) => Municipality(id: doc.id, name: doc['name']))
              .toList();
          isLoadingMunicipalities = false;
        });
      }
    } catch (e) {
      print("自治体リストの取得エラー: $e");
      if (mounted) {
        setState(() {
          isLoadingMunicipalities = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('自治体リストの読み込みに失敗しました。')));
      }
    }
  }

  Future<void> _fetchAllSchools() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection('schools').get();
      if (mounted) {
        setState(() {
          allSchools = snapshot.docs
              .map((doc) => School(id: doc.id, name: doc['name'], municipalityId: doc['municipalityId'] ?? ''))
              .toList();
          isLoadingSchools = false;
        });
      }
    } catch (e) {
      print("学校リストの取得エラー: $e");
      if (mounted) {
        setState(() {
          isLoadingSchools = false;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('学校リストの読み込みに失敗しました。')));
      }
    }
  }

  void _onMunicipalityChanged(Municipality? newValue) {
    setState(() {
      selectedMunicipality = newValue;
      selectedSchool = null;
      if (newValue != null) {
        filteredSchools = allSchools.where((school) => school.municipalityId == newValue.id).toList();
      } else {
        filteredSchools = [];
      }
    });
  }

  void _onSchoolChanged(School? newValue) {
    setState(() {
      selectedSchool = newValue;
    });
  }

  Future<void> _loginUser() async {
    // ログイン処理前にフォーカスを外す
    FocusScope.of(context).unfocus();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('メールアドレスとパスワードを入力してください。')),
      );
      return;
    }
    // ... (ログイン処理の残りは変更なし)
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      print('ログイン成功: ${userCredential.user?.uid}');
      await _saveLastEmail(email);

      if (mounted) {
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) => StudentReservePage(title: "予約")));
      }
    } on FirebaseAuthException catch (e) {
      String message = 'ログインに失敗しました。';
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'メールアドレスまたはパスワードが正しくありません。';
      } else if (e.code == 'invalid-email') {
        message = 'メールアドレスの形式が正しくありません。';
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
    }
  }

  void _navigateToRegistration() {
    // 新規登録処理前にフォーカスを外す
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentRegistrationPage(
          title: "新規登録",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector( // 画面全体を GestureDetector でラップ
      onTap: () {
        // キーボード以外の場所をタップしたらフォーカスを外してキーボードを閉じる
        FocusScope.of(context).unfocus();
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
          backgroundColor: Colors.blue,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea( // SafeArea で body をラップ
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    height: 350, // 画像の高さをさらに減らす (調整可能)
                    child: Image.asset('images/school.jpg'),
                  ),
                  const SizedBox(height: 15), // 少し間隔を詰める


                  TextField(
                    controller: _emailController,
                    focusNode: _emailFocusNode, // FocusNode を割り当て
                    decoration: const InputDecoration(
                      labelText: 'メールアドレス（ログインID）',
                      hintText: 'email@example.com',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next, // 次のフィールドへ
                    onSubmitted: (_) { // Enterキーで次のフィールドへフォーカス
                      FocusScope.of(context).requestFocus(_passwordFocusNode);
                    },
                    autofillHints: const [AutofillHints.email],
                  ),
                  const SizedBox(height: 10), // 少し間隔を詰める

                  TextField(
                    controller: _passwordController,
                    focusNode: _passwordFocusNode, // FocusNode を割り当て
                    decoration: const InputDecoration(
                      labelText: 'パスワード',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.done, // 完了アクション
                    onSubmitted: (_) { // Enterキーでログイン処理
                      _loginUser();
                    },
                    autofillHints: const [AutofillHints.password],
                  ),
                  const SizedBox(height: 25), // 少し間隔を詰める

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      SizedBox(
                        height: 50, // ボタンの高さを少し調整
                        width: MediaQuery.of(context).size.width * 0.40, // 幅も調整
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(fontSize: 20)), // フォントサイズ調整
                          onPressed: _navigateToRegistration,
                          child: const Text("新規登録"),
                        ),
                      ),
                      SizedBox(
                        height: 50, // ボタンの高さを少し調整
                        width: MediaQuery.of(context).size.width * 0.40, // 幅も調整
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(fontSize: 20)), // フォントサイズ調整
                          onPressed: _loginUser,
                          child: const Text("ログイン"),
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

