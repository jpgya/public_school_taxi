import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Municipality クラスはここでは不要になります

class LocalRegistrationPageModified extends ConsumerStatefulWidget {
  const LocalRegistrationPageModified({super.key, required this.title});

  final String title;

  @override
  LocalRegistrationPageModifiedState createState() =>
      LocalRegistrationPageModifiedState();
}

class LocalRegistrationPageModifiedState
    extends ConsumerState<LocalRegistrationPageModified> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // TextEditingControllers
  final TextEditingController _municipalityFullNameController = TextEditingController(); // 都道府県含む自治体名
  final TextEditingController _displayNameController = TextEditingController(); // 担当者・アカウント表示名
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _invitationCodeController = TextEditingController();

  // 状態管理
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _municipalityFullNameController.dispose();
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _invitationCodeController.dispose();
    super.dispose();
  }

  // 招待コードの検証 (前回のものを流用、コレクション名などを確認)
  Future<DocumentSnapshot?> _validateLocalInvitationCode(String code) async {
    if (code.isEmpty) {
      if (mounted) setState(() => _errorMessage = '招待コードを入力してください。');
      return null;
    }
    if (mounted) setState(() => _isLoading = true);
    _errorMessage = null;

    try {
      final querySnapshot = await _firestore
          .collection('local_invitation_codes') // ★招待コードのコレクション名
          .where('code', isEqualTo: code)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final data = doc.data() as Map<String, dynamic>;

        // 有効期限、使用済み、使用回数などのチェック (前回のコードと同様)
        if (data.containsKey('expiresAt') && data['expiresAt'] != null) {
          final expiresAt = (data['expiresAt'] as Timestamp).toDate();
          if (expiresAt.isBefore(DateTime.now())) {
            if (mounted) setState(() => _errorMessage = 'この招待コードは有効期限が切れています。');
            return null;
          }
        }
        if (data['isUsed'] == true) {
          if (mounted) setState(() => _errorMessage = 'この招待コードは既に使用されています。');
          return null;
        }
        final int? usageLimit = data['usageLimit'] as int?;
        final int timesUsed = (data['timesUsed'] as int?) ?? 0;
        if (usageLimit != null && timesUsed >= usageLimit) {
          if (mounted) setState(() => _errorMessage = 'この招待コードは使用上限に達しました。');
          return null;
        }
        return doc;
      } else {
        if (mounted) setState(() => _errorMessage = '招待コードが見つかりません。');
        return null;
      }
    } catch (e) {
      print('招待コード検証エラー (LocalRegistrationModified): $e');
      if (mounted) setState(() => _errorMessage = '招待コードの検証中にエラーが発生しました。');
      return null;
    }
  }


  Future<void> _registerLocalUser() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!mounted) return; //早期リターン
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final String municipalityFullName = _municipalityFullNameController.text.trim();
    final String displayName = _displayNameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();
    final String invitationCode = _invitationCodeController.text.trim();

    User? newUser; // tryブロックの外で宣言

    try {
      // 1. 招待コードの検証
      final invitationDocSnapshot = await _validateLocalInvitationCode(invitationCode);

      if (invitationDocSnapshot == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          // _errorMessage は _validateLocalInvitationCode 内で設定される想定
        }
        return;
      }

      // 2. Firebase Authenticationでユーザー作成
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      newUser = userCredential.user; // ここで代入

      if (newUser == null) {
        // 基本的には発生しないはずだが、念のため
        throw Exception('Firebaseユーザーの作成に失敗しましたが、エラーは報告されませんでした。');
      }

      await newUser!.updateDisplayName(displayName.isNotEmpty ? displayName : municipalityFullName);

      // 3 & 4. Firestoreへの書き込みをトランザクションで実行
      await _firestore.runTransaction((transaction) async {
        final newUserDocRef = _firestore.collection('local_users').doc(newUser!.uid); // 定数化推奨
        final invitationCodeDocRef = _firestore.collection('local_invitation_codes').doc(invitationDocSnapshot.id); // 定数化推奨

        // ユーザー情報をセット
        transaction.set(newUserDocRef, {
          'uid': newUser!.uid, // UserFields.uid
          'email': newUser!.email, // UserFields.email
          'displayName': displayName.isNotEmpty ? displayName : municipalityFullName, // UserFields.displayName
          'municipalityFullName': municipalityFullName, // UserFields.municipalityFullName
          'role': 'local', // UserFields.role
          'registeredAt': Timestamp.now(), // UserFields.registeredAt
          'usedInvitationCode': invitationCode, // UserFields.usedInvitationCode
          'isActive': true, // UserFields.isActive
        });

        // 招待コードの使用状況を更新
        transaction.update(invitationCodeDocRef, {
          'timesUsed': FieldValue.increment(1), // InvitationCodeFields.timesUsed
          'lastUsedBy': newUser!.uid, // InvitationCodeFields.lastUsedBy
          'lastUsedAt': Timestamp.now(), // InvitationCodeFields.lastUsedAt
        });
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('自治体アカウントの登録が完了しました。ログインしてください。'),
            backgroundColor: Colors.green),
      );
      if (Navigator.canPop(context)) {
        Navigator.pop(context); // ログインページに戻る
      }

    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = '登録に失敗しました。';
      if (e.code == 'weak-password') {
        message = 'パスワードは6文字以上にしてください。';
      } else if (e.code == 'email-already-in-use') {
        message = 'このメールアドレスは既に使用されています。';
      } else if (e.code == 'invalid-email') {
        message = 'メールアドレスの形式が正しくありません。';
      } else {
        // その他のFirebaseAuthException
        print('FirebaseAuthException (LocalRegistration): ${e.code} - ${e.message}');
      }
      setState(() => _errorMessage = message);
    } catch (e, s) { // s は StackTrace
      if (!mounted) return;
      print('予期せぬエラー (LocalRegistration): $e\n$s'); // スタックトレースも出力
      setState(() => _errorMessage = '予期せぬエラーが発生しました。詳細はシステム管理者にお問い合わせください。');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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
        backgroundColor: Colors.orange,
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
                  '自治体アカウント作成',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),

                // 自治体名 (都道府県含む)
                TextFormField(
                  controller: _municipalityFullNameController,
                  decoration: const InputDecoration(
                    labelText: '自治体名 (都道府県から入力) *',
                    hintText: '例: 宮城県仙台市, 東京都千代田区',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_city),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '自治体名を入力してください。';
                    }
                    // 簡単な形式チェック (例: "県"や"都"や"府"や"道"と"市"や"町"や"村"や"区"を含むか)
                    if (!value.contains(RegExp(r'[都道府県]')) || !value.contains(RegExp(r'[市区町村]'))) {
                      return '都道府県名から市区町村名まで入力してください。';
                    }
                    return null;
                  },
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),

                // 表示名 (任意)
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: '担当者・アカウント表示名 (任意)',
                    hintText: '例: 仙台市役所担当, 山田太郎',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  keyboardType: TextInputType.name,
                  // バリデーションは任意なので不要
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),

                // メールアドレス
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'メールアドレス (ログインID) *',
                    hintText: 'account@example.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'メールアドレスを入力してください。';
                    }
                    final emailRegex = RegExp(
                        r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
                    if (!emailRegex.hasMatch(value)) {
                      return '有効なメールアドレスを入力してください。';
                    }
                    return null;
                  },
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),

                // パスワード
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'パスワード *',
                    hintText: '6文字以上',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
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
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),

                // パスワード確認
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'パスワード（確認）*',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
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
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),

                // 招待コード
                TextFormField(
                  controller: _invitationCodeController,
                  decoration: const InputDecoration(
                    labelText: '招待コード *',
                    hintText: 'システム管理者から発行されたコード',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '招待コードを入力してください。';
                    }
                    return null;
                  },
                  enabled: !_isLoading,
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
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _registerLocalUser,
                  child: const Text("アカウントを作成"),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("既にアカウントをお持ちですか？ "),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                      child: const Text("ログイン"),
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

