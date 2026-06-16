import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

// استيراد الخدمة لجلب التوكن
import 'notification_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool isLogin = true;
  bool loading = false;
  
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final String internalPassword = "RahaInternalPassword123!";

  // متغير لحفظ المنطقة المختارة
  String? _selectedRegion;
  final List<String> _regions = ["أم درمان", "بحري", "شرق النيل", "الخرطوم"];

  String formatSudanPhone(String input) {
    String clean = input.replaceAll(RegExp(r'\D'), '');
    if (clean.startsWith('0')) return "249${clean.substring(1)}";
    if (!clean.startsWith('249')) return "249$clean";
    return clean;
  }

  // الدالة المحدثة: تقوم بفحص التوكن وتحديثه فقط إذا كان جديداً
  Future<void> _updateUserToken(String uid) async {
    try {
      String? newToken = await NotificationService.getDeviceToken();
      if (newToken != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        
        // جلب التوكن القديم من Firestore للمقارنة
        String? oldToken = userDoc.data()?['fcmToken'];

        if (newToken != oldToken) {
          await FirebaseFirestore.instance.collection('users').doc(uid).update({
            'fcmToken': newToken,
            'lastTokenUpdate': FieldValue.serverTimestamp(),
          });
          debugPrint("FCM Token updated successfully ✅");
        } else {
          debugPrint("FCM Token is already up to date.");
        }
      }
    } catch (e) {
      debugPrint("Error updating token: $e");
    }
  }

  Future<void> handleGoogleSignIn() async {
    setState(() => loading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => loading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).get();
      
      if (!userDoc.exists) {
        await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
          'uid': userCredential.user!.uid,
          'fullName': userCredential.user!.displayName ?? "مستخدم جوجل",
          'phone': userCredential.user!.phoneNumber ?? "",
          'email': userCredential.user!.email,
          'createdAt': FieldValue.serverTimestamp(),
          'provider': 'google',
          'adminType': 'user', // القيمة الافتراضية
        });
      }

      // تحديث التوكن عند تسجيل الدخول بجوجل
      await _updateUserToken(userCredential.user!.uid);

      showSnackBar("مرحباً بك عبر جوجل! 🌐");
      if (mounted) Navigator.pushReplacementNamed(context, '/home');

    } catch (e) {
      debugPrint("Google Sign-In Error: $e");
      showSnackBar("فشل تسجيل الدخول عبر جوجل");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> handleSubmit() async {
    if (_phoneController.text.isEmpty || (!isLogin && (_nameController.text.isEmpty || _selectedRegion == null))) {
      showSnackBar("الرجاء ملء كافة البيانات واختيار المنطقة");
      return;
    }

    setState(() => loading = true);
    String formattedPhone = formatSudanPhone(_phoneController.text);
    String fakeEmail = "$formattedPhone@raha.sd";

    try {
      UserCredential userCredential;
      if (isLogin) {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: fakeEmail,
          password: internalPassword,
        );
        showSnackBar("مرحباً بك مجدداً! 🚀");
      } else {
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: fakeEmail,
          password: internalPassword,
        );

        await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
          'uid': userCredential.user!.uid,
          'fullName': _nameController.text,
          'phone': formattedPhone,
          'email': fakeEmail,
          'region': _selectedRegion, // حفظ المنطقة المختارة
          'createdAt': FieldValue.serverTimestamp(),
          'adminType': 'user',
        });
        showSnackBar("تم إنشاء حسابك بنجاح ✨");
      }

      // تحديث التوكن عند تسجيل الدخول أو إنشاء الحساب التقليدي
      await _updateUserToken(userCredential.user!.uid);

      if (mounted) Navigator.pushReplacementNamed(context, '/home');

    } on FirebaseAuthException catch (e) {
      String msg = "حدث خطأ في العملية";
      if (e.code == 'user-not-found' || e.code == 'invalid-credential' || e.code == 'wrong-password') {
        msg = "بيانات الدخول غير صحيحة أو الرقم غير مسجل.";
      } else if (e.code == 'email-already-in-use') {
        msg = "هذا الرقم مسجل مسبقاً، جرب تسجيل الدخول.";
      }
      showSnackBar(msg);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Aljazeera')), 
        backgroundColor: Colors.black,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            children: [
              const SizedBox(height: 80),
              // شعار التطبيق
              Hero(
                tag: 'logo',
                child: Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Image.asset(
                      'assets/images/logo.png', 
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.storefront_outlined, size: 50),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isLogin ? "تسجيل دخول" : "تسجيل مستخدم جديد",
                style: const TextStyle(
                  fontSize: 22, 
                  fontWeight: FontWeight.w900, 
                  fontStyle: FontStyle.italic,
                  fontFamily: 'Aljazeera',
                ),
              ),
              
              const SizedBox(height: 40),

              // زر جوجل (خيار أول مع أيقونة جوجل)
              SizedBox(
                width: double.infinity,
                height: 60,
                child: OutlinedButton(
                  onPressed: loading ? null : handleGoogleSignIn,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.network(
                        'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1200px-Google_%22G%22_logo.svg.png',
                        height: 24,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        "الدخول بواسطة جوجل", 
                        style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontFamily: 'Aljazeera'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 25),

              // فاصل بسيط بين خيار جوجل والتسجيل العادي
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey[200])),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text("أو", style: TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'Aljazeera')),
                  ),
                  Expanded(child: Divider(color: Colors.grey[200])),
                ],
              ),

              const SizedBox(height: 25),

              if (!isLogin) ...[
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text("الاسم الكامل", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Aljazeera')),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  textAlign: TextAlign.right,
                  // --- التعديل هنا ---
                  keyboardType: TextInputType.name, // لوحة مفاتيح مخصصة للأسماء
                  textCapitalization: TextCapitalization.words, // تكبير أول حرف من كل كلمة تلقائياً
                  // ------------------
                  style: const TextStyle(fontFamily: 'Aljazeera'),
                  decoration: InputDecoration(
                    hintText: "اكتب هنا اسمك ثلاثي",
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13, fontFamily: 'Aljazeera'),
                    fillColor: Colors.grey[50],
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),

                // حقل اختيار المنطقة (يظهر فقط عند إنشاء الحساب)
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text("حدد المنطقة", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Aljazeera')),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedRegion,
                      isExpanded: true,
                      hint: Text("اختر منطقتك", style: TextStyle(color: Colors.grey[400], fontSize: 13, fontFamily: 'Aljazeera')),
                      icon: const Icon(Icons.location_on_outlined, color: Colors.grey),
                      items: _regions.map((String region) {
                        return DropdownMenuItem<String>(
                          value: region,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(region, style: const TextStyle(fontSize: 14, fontFamily: 'Aljazeera')),
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedRegion = newValue;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              const Align(
                alignment: Alignment.centerRight,
                child: Text("رقم الهاتف", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Aljazeera')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textAlign: TextAlign.left,
                style: const TextStyle(fontFamily: 'Aljazeera'),
                decoration: InputDecoration(
                  hintText: "0XXXXXXXXX",
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13, fontFamily: 'Aljazeera'),
                  fillColor: Colors.grey[50],
                  filled: true,
                  prefixIcon: const Icon(Icons.phone_android, size: 20, color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),

              const SizedBox(height: 30),

              // زر تسجيل الدخول (أسود) / زر إنشاء حساب (أزرق)
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: loading ? null : handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLogin ? Colors.black : Colors.blueAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: loading 
                    ? const SizedBox(width: 25, height: 25, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                    : Text(
                        isLogin ? "تسجيل الدخول 🚀" : "إتمام التسجيل ✨", 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Aljazeera'),
                      ),
                ),
              ),

              const SizedBox(height: 20),

              // تبديل بين تسجيل الدخول وإنشاء الحساب
              TextButton(
                onPressed: () => setState(() {
                  isLogin = !isLogin;
                }),
                child: Text(
                  isLogin ? "ليس لديك حساب؟ إنشاء حساب جديد ✨" : "لديك حساب بالفعل؟ سجل دخولك 🚀",
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Aljazeera'),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
