import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// dropdown_search と Municipality, Schoolクラスのインポートは、
// 招待コードに学校情報が含まれない場合に別途必要になります。
// 今回は招待コードにschoolIdが含まれるStudentRegistrationPageの形式に合わせます。

// import '../student/student_page.dart'; // ログインページに戻る場合など (適宜変更)

class TaxiDriverLoginPage extends ConsumerStatefulWidget {
  const TaxiDriverLoginPage({super.key, required this.title});

  final String title;

  @override
  TaxiDriverLoginPageState createState() => TaxiDriverLoginPageState();
}

class TaxiDriverLoginPageState extends ConsumerState<TaxiDriverLoginPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // TextEditingControllers
  final TextEditingController _displayNameController = TextEditingController(); // ドライバー名
  final TextEditingController _maxNumController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _invitationCodeController = TextEditingController(); // 必須とするか運用による

  // 状態管理
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;


  @override
  void dispose() {
    _displayNameController.dispose();
    _maxNumController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _invitationCodeController.dispose();
    super.dispose();
  }

  // 招待コードの検証ロジック (StudentRegistrationPageと同様)
  // Firestoreの 'invitation_codes' コレクションの 'code' フィールドで検索し、
  // ドキュメント内に 'schoolId' (またはドライバーの場合は 'companyId' など関連情報) が含まれることを期待する
  Future<DocumentSnapshot?> _validateInvitationCode(String code) async {
    if (code.isEmpty) {
      // 招待コードが任意の場合、または招待コードなしの登録フローがある場合は、このチェックを変更
      if (mounted) {
        setState(() {
          _errorMessage = '招待コードを入力してください。'; // 招待コードが必須でない場合はこのエラーは不要
        });
      }
      return null;
    }

    if (mounted) {
      setState(() {
        _isLoading = true; // isLoadingは _registerDriver 内で制御するのでここでは不要かも
        _errorMessage = null;
      });
    }

    try {
      // ドライバー用の招待コードは、'invitation_codes_drivers' のような別のコレクションにするか、
      // 'invitation_codes' 内で type: 'driver' のようなフィールドで区別することを推奨
      final querySnapshot = await _firestore
          .collection('invitation_codes_drivers') // ドライバー用の招待コードコレクション名（例）
          .where('code', isEqualTo: code)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        // ドライバー登録に必要な情報が招待コードドキュメントに含まれているか確認
        // 例: 'companyId', 'allowedSchoolIds' (配列), 'areaId' など
        // ここでは仮に 'companyId' と 'defaultSchoolId' があるとする
        final data = doc.data() as Map<String, dynamic>;
        if (doc.exists && data.containsKey('companyId')) { // ドライバーが所属する会社IDなど
          return doc;
        } else {
          if (mounted) setState(() => _errorMessage = '招待コードの情報が正しくありません。');
          return null;
        }
      } else {
        if (mounted) setState(() => _errorMessage = '有効な招待コードが見つかりません。');
        return null;
      }
    } catch (e) {
      print('招待コード検証エラー: $e');
      if (mounted) setState(() => _errorMessage = '招待コードの検証中にエラーが発生しました。');
      return null;
    } finally {
      // _isLoading は _registerDriver で制御するため、ここでは解除しない
    }
  }


  Future<void> _registerDriver() async { // StudentRegistrationPageの_registerUserに相当
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
    final int maxNum = _maxNumController.text.trim().isEmpty ? 0 : int.parse(_maxNumController.text.trim());
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();
    final String invitationCode = _invitationCodeController.text.trim(); // 招待コードが任意の場合は処理を調整

    try {
      // 1. 招待コードの検証 (招待コードを使用する場合)
      // もし招待コードが必須でない、または別の登録フローがある場合は、この部分は条件分岐するか削除
      DocumentSnapshot? invitationDoc;
      // if (invitationCode.isNotEmpty) { // 招待コードが入力されていれば検証
      invitationDoc = await _validateInvitationCode(invitationCode);
      if (invitationDoc == null) {
        // _validateInvitationCode内でerrorMessageが設定されるのでここでは不要な場合もある
        if (_errorMessage == null && mounted) {
          setState(() { _errorMessage = '招待コードが無効か、既に使用されています。'; });
        }
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      // }
      // else {
      //   // 招待コードなしでの登録ロジック (例: 管理者による承認が必要など)
      //   // ここでは招待コードが必須という前提で進めます
      //   if (mounted) {
      //       setState(() { _errorMessage = '招待コードを入力してください。'; _isLoading = false;});
      //   }
      //   return;
      // }


      // 招待コードから必要な情報を取得 (例)
      final invitationData = invitationDoc.data() as Map<String, dynamic>;
      final String companyId = invitationData['companyId']; // ドライバーが所属する会社ID
      final String? assignedSchoolId = invitationData['defaultSchoolId']; // 初期割り当て学校ID (任意)
      // final List<String>? allowedAreaIds = List<String>.from(invitationData['allowedAreaIds'] ?? []);


      // 2. Firebase Authenticationでユーザー作成
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? newDriver = userCredential.user;

      if (newDriver != null) {
        await newDriver.updateDisplayName(displayName); // Firebaseユーザープロファイルに表示名を設定

        // 3. Firestoreの'drivers'コレクションにドライバー情報を保存
        await _firestore.collection('drivers').doc(newDriver.uid).set({
          'uid': newDriver.uid,
          'email': newDriver.email,
          'displayName': displayName,
          'maxNum': maxNum,
          'companyId': companyId, // 招待コードから取得した会社ID
          if (assignedSchoolId != null) 'assignedSchoolId': assignedSchoolId, // 初期割り当て学校
          // 'allowedAreaIds': allowedAreaIds, // 運行許可エリア
          'registeredAt': Timestamp.now(),
          'usedInvitationCode': invitationCode, // 使用した招待コード
          'role': 'driver', // ロールを'driver'に設定
          'isActive': true, // 初期状態は有効 (管理者が変更できるようにする)
        });

        // (任意) 招待コードの使用済みフラグを更新
        await _firestore.collection('invitation_codes_drivers').doc(invitationDoc.id).update({
          'isUsed': true,
          'usedBy': newDriver.uid,
          'usedAt': Timestamp.now(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('タクシーアカウントが作成されました。ログインしてください。'), backgroundColor: Colors.green),
          );
          // 登録成功後、ログインページに遷移
          if (Navigator.canPop(context)) {
            Navigator.pop(context); // 登録画面を閉じてログイン画面に戻る
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      String message = '登録に失敗しました。';
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
        backgroundColor: Colors.green, // ドライバー向けの色に変更
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.of(context).pop();
            }
          },
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
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'タクシー車両アカウント作成', // タイトル変更
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 25),

                // 車両名 (表示名)
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'ナンバープレート',
                    hintText: '例: あ１２－３４',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.local_taxi),
                  ),
                  keyboardType: TextInputType.name,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'ナンバープレートを入力してください。';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 最大乗車人数
                TextFormField(
                  controller: _maxNumController,
                  decoration: const InputDecoration(
                    labelText: '最大乗車人数',
                    hintText: '例: 4　(半角入力)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.local_taxi),
                  ),
                  keyboardType: TextInputType.name,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '最大乗車人数を入力してください。';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // メールアドレス
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'メールアドレス（ログインID）',
                    hintText: 'driver@example.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'メールアドレスを入力してください。';
                    }
                    final emailRegex = RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
                    if (!emailRegex.hasMatch(value)) {
                      return '有効なメールアドレスを入力してください。';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

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

                // 招待コード (運用に応じて必須/任意を変更)
                TextFormField(
                  controller: _invitationCodeController,
                  decoration: const InputDecoration(
                    labelText: '招待コード', // 「所属会社/管理者からの招待コード」など、より具体的に
                    hintText: '配布されたコードを入力',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                  validator: (value) {
                    // 招待コードが必須でない場合は、isEmptyチェックを緩めるか削除
                    if (value == null || value.isEmpty) {
                      return '招待コードを入力してください。';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 25),

                // エラーメッセージ表示
                if (_errorMessage != null && _errorMessage!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // 新規登録ボタン
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green, // ボタンの色を変更
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _registerDriver,
                  child: const Text("アカウント作成"),
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("既にアカウントをお持ちですか？ "),
                    TextButton(
                      onPressed: () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context); // ログイン画面に戻る
                        }
                        // else {
                        //   // ログイン画面に直接遷移する (例: ルーティングを使用)
                        //   // Navigator.of(context).pushReplacementNamed('/driver_login');
                        // }
                      },
                      child: Text("ログイン", style: TextStyle(color: Colors.green.shade700)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

