import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // ConsumerStatefulWidgetのため
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// StudentPage から Municipality と School クラスをインポートすることを想定
// もし別の場所にある場合は、正しいパスに置き換えてください。
// 例: import '../models/municipality.dart';
//     import '../models/school.dart';
// 今回は student.dart にあると仮定します。
// import 'package:school_taxi/student/student.dart'; // ログインページに戻る場合など

class StudentRegistrationPage extends ConsumerStatefulWidget {
  const StudentRegistrationPage({super.key, required this.title});

  final String title;

  @override
  StudentRegistrationPageState createState() => StudentRegistrationPageState();
}

class StudentRegistrationPageState extends ConsumerState<StudentRegistrationPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // TextEditingControllers
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _invitationCodeController = TextEditingController();
  final TextEditingController _addressController = TextEditingController(); // ★★★ 住所用コントローラー追加 ★★★

  // 状態管理
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;


  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _invitationCodeController.dispose();
    _addressController.dispose(); // ★★★ disposeに追加 ★★★
    super.dispose();
  }

  Future<DocumentSnapshot?> _validateInvitationCode(String code) async {
    if (code.isEmpty) {
      if (mounted) {
        setState(() {
          _errorMessage = '招待コードを入力してください。';
        });
      }
      return null;
    }
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final querySnapshot = await _firestore
          .collection('invitation_codes') // Firestoreのコレクション名
          .where('code', isEqualTo: code)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        if (doc.exists && (doc.data() as Map<String, dynamic>).containsKey('schoolId')) {
          return doc;
        } else {
          if (mounted) setState(() => _errorMessage = '招待コードのデータに学校情報が含まれていません。');
          return null;
        }
      } else {
        if (mounted) setState(() => _errorMessage = '招待コードが見つかりません。');
        return null;
      }
    } catch (e) {
      print('招待コード検証エラー: $e');
      if (mounted) setState(() => _errorMessage = '招待コードの検証中にエラーが発生しました。');
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _registerUser() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final String displayName = _displayNameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();
    final String invitationCode = _invitationCodeController.text.trim();
    final String address = _addressController.text.trim(); // ★★★ 住所を取得 ★★★

    try {
      final invitationDoc = await _validateInvitationCode(invitationCode);

      if (invitationDoc == null) {
        if (_errorMessage == null && mounted) {
          setState(() { _errorMessage = '招待コードが無効です。'; });
        }
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final String schoolId = (invitationDoc.data() as Map<String, dynamic>)['schoolId'];
      final String? schoolName = (invitationDoc.data() as Map<String, dynamic>)['schoolName'];


      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? newUser = userCredential.user;

      if (newUser != null) {
        await newUser.updateDisplayName(displayName);

        // ★★★ Firestoreに保存するデータに Address を追加 ★★★
        await _firestore.collection('Users').doc(newUser.uid).set({
          'uid': newUser.uid,
          'email': newUser.email,
          'displayName': displayName,
          'Address': address, // ★★★ Addressフィールドを追加 ★★★
          'schoolId': schoolId,
          if (schoolName != null) 'schoolName': schoolName,
          'registeredAt': Timestamp.now(),
          'usedInvitationCode': invitationCode,
          'role': 'student',
        });

        // (任意) 招待コードの使用済みフラグを更新
        // await _firestore.collection('invitation_codes').doc(invitationDoc.id).update({'isUsed': true});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('登録が完了しました。ログインしてください。'), backgroundColor: Colors.green),
          );
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      String message = '登録に失敗しました。もう一度お試しください。';
      if (e.code == 'weak-password') {
        message = 'パスワードは6文字以上にしてください。';
      } else if (e.code == 'email-already-in-use') {
        message = 'このメールアドレスは既に使用されています。';
      } else if (e.code == 'invalid-email') {
        message = 'メールアドレスの形式が正しくありません。';
      }
      print('FirebaseAuthException: ${e.code} - ${e.message}');
      if (mounted) {
        setState(() {
          _errorMessage = message;
        });
      }
    } catch (e) {
      print('予期せぬエラー: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '予期せぬエラーが発生しました。しばらくしてから再度お試しください。';
        });
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

        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(widget.title, style: const TextStyle(color: Colors.white)),
            SizedBox(width: MediaQuery.of(context).size.width * 0.16)
          ],
        ),
        backgroundColor: Colors.blue,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: 20),
                Text(
                  '生徒アカウント作成',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),

                // 表示名
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: '名前',
                    hintText: '例: 山田 太郎',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  keyboardType: TextInputType.name,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '名前を入力してください。';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // メールアドレス
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'メールアドレス',
                    hintText: 'example@example.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'メールアドレスを入力してください。';
                    }
                    final emailRegex = RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
                    if (!emailRegex.hasMatch(value)) {
                      return '有効なメールアドレスを入力してください。';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // ★★★ 住所入力フィールド追加 ★★★
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: '住所',
                    hintText: '例: 東京都千代田区1-1-1',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.home_outlined),
                  ),
                  keyboardType: TextInputType.streetAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '住所を入力してください。';
                    }
                    // 必要であれば、より詳細な住所のバリデーションを追加
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // ★★★ ここまで住所入力フィールド ★★★

                // パスワード
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'パスワード',
                    hintText: '6文字以上',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'パスワードを入力してください。';
                    }
                    if (value.length < 6) {
                      return 'パスワードは6文字以上で入力してください。';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // パスワード確認
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'パスワード（確認）',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureConfirmPassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '確認用パスワードを入力してください。';
                    }
                    if (value != _passwordController.text) {
                      return 'パスワードが一致しません。';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 招待コード
                TextFormField(
                  controller: _invitationCodeController,
                  decoration: const InputDecoration(
                    labelText: '招待コード',
                    hintText: '学校から配布されたコード',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '招待コードを入力してください。';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 30),

                if (_errorMessage != null && _errorMessage!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),

                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _registerUser,
                  child: const Text("アカウントを作成"),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("既にアカウントをお持ちですか？"),
                    TextButton(
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                      child: const Text("ログイン"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
