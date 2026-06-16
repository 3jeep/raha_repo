import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'package:flutter_localizations/flutter_localizations.dart'; 
import 'dart:async'; 
import 'package:url_launcher/url_launcher.dart';
import 'firebase_options.dart';

// استيراد الخدمات والصفحات
import 'notification_service.dart'; 
import 'single_visit_page.dart'; 
import 'my_bookings_page.dart';      
import 'login_page.dart';
import 'offers_page.dart';
import 'profile_page.dart';
import 'laundry_checkout_page.dart'; 
import 'special_offer_checkout_page.dart'; 
import 'multi_visit_contract_page.dart'; 
import 'notifications_page.dart'; 
import 'admin_category_page.dart'; 
import 'handyman_hub_page.dart'; 

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    
    // 🌟 ضع الكود الجديد هنا بالتحديد بعد التهيأة مباشرة 🌟
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true, // تفعيل الحفظ على القرص المحلي ليعمل بدون إنترنت وبسرعة
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED, // مساحة كاش مفتوحة وغير محدودة لسرعة فائقة
    );

    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await NotificationService.init();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    runApp(const RahaApp());
  } catch (e) {
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: Text("Firebase Error: $e")))
    ));
  }
}


class RahaApp extends StatelessWidget {
  const RahaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'راحه RAHA',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', 'AE')],
      locale: const Locale('ar', 'AE'), 
      theme: ThemeData(
        primaryColor: const Color(0xFF1E293B),
        fontFamily: 'Cairo', 
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CustomLoadingWidget(message: "انتظر لحظات...");
          }
          if (snapshot.hasData && snapshot.data != null) {
            return const HomeScreen();
          }
          return const LoginPage();
        },
      ),
      routes: {
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}

class CustomLoadingWidget extends StatelessWidget {
  final String message;
  const CustomLoadingWidget( {super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/logo.png', width: 120, height: 120, fit: BoxFit.contain),
            const SizedBox(height: 25),
            Text(message, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 15),
            const SizedBox(width: 60, child: LinearProgressIndicator(color: Colors.blue)),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _completedVisitsCount = 0;
  List<Map<String, dynamic>> _specialPackages = [];
  Map<String, dynamic>? _laundryPrices;
  double? _officialSinglePrice; 
  bool _isLoading = true;
  bool _isAdmin = false; // هل هو أدمن بشكل عام
  bool _isProfileIncomplete = false; 
  String? _adminType; 
  String? _whatsappNumber;
  DateTime _screenInitTime = DateTime.now();

  StreamSubscription? _adminSub;
  StreamSubscription? _laundryAdminSub;
  StreamSubscription? _contractsSub; 
  StreamSubscription? _userSub;

  @override
  void initState() {
    super.initState();
    _screenInitTime = DateTime.now();
    _initData();
    _setupForegroundNotifications(); 
  }

  @override
  void dispose() {
    _adminSub?.cancel();
    _laundryAdminSub?.cancel();
    _contractsSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }

  void _setupForegroundNotifications() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        NotificationService.showNotification(
          message.notification!.title ?? "تنبيه من راحة 🔔",
          message.notification!.body ?? "",
        );
      }
    });
  }

  void _listenToRoleBasedOrders() {
    _adminSub?.cancel();
    _laundryAdminSub?.cancel();
    _contractsSub?.cancel();
    _userSub?.cancel();

    // إشعارات الحجوزات الفردية
    _adminSub = FirebaseFirestore.instance
        .collection('bookings')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        var data = change.doc.data();
        if (data == null) continue;
        Timestamp? timeStamp = (change.type == DocumentChangeType.added) 
            ? data['createdAt'] as Timestamp? 
            : data['updatedAt'] as Timestamp?;

        if (timeStamp != null && timeStamp.toDate().isAfter(_screenInitTime)) {
          String orderId = change.doc.id.substring(0, 5);
          String clientName = data['userName'] ?? "عميل";
          String status = data['status'] ?? "";

          if (change.type == DocumentChangeType.added) {
            // إشعار للأدمن (super أو cleaning)
            if (_isAdmin && (_adminType == "super" || _adminType == "cleaning") && status == 'pending') {
              NotificationService.showNotification(
                "طلب زيارة جديد 🏠",
                "قام $clientName بطلب خدمة جديدة (رقم $orderId). يرجى المراجعة والتأكيد.",
                targetSection: 'admin'
              );
            }
          } else if (change.type == DocumentChangeType.modified) {
            if (status == 'confirmed') {
              NotificationService.showNotification("تم تأكيد حجزك ✅", "عزيزي $clientName، تم تأكيد طلبك رقم $orderId بنجاح. فريقنا سيصلك في الموعد.");
            } else if (status == 'started') {
              NotificationService.showNotification("بدأ العمل الآن 🚀", "فريق راحة بدأ تنفيذ المهمة لطلبك رقم $orderId. نتمنى لك خدمة متميزة.");
            } else if (status == 'completed') {
              NotificationService.showNotification("تم إنجاز المهمة ✨", "تم إتمام طلبك رقم $orderId بنجاح. شكراً لثقتك براحة!", targetSection: 'all');
            }
          }
        }
      }
    });

    // إشعارات غسيل الملابس
    _laundryAdminSub = FirebaseFirestore.instance
        .collection('laundry_orders')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        var data = change.doc.data();
        if (data == null) continue;
        Timestamp? timeStamp = (change.type == DocumentChangeType.added) 
            ? data['createdAt'] as Timestamp? 
            : data['updatedAt'] as Timestamp?;

        if (timeStamp != null && timeStamp.toDate().isAfter(_screenInitTime)) {
          String orderId = change.doc.id.substring(0, 5);
          String status = data['status'] ?? "";
          String clientName = data['userName'] ?? "عميل";

          if (change.type == DocumentChangeType.added) {
            // إشعار للأدمن (super أو laundry)
            if (_isAdmin && (_adminType == "super" || _adminType == "laundry") && status == 'pending') {
              NotificationService.showNotification(
                "طلب غسيل جديد 🧺",
                "وصل طلب غسيل جديد من العميل $clientName (رقم $orderId).",
                targetSection: 'admin'
              );
            }
          } else if (change.type == DocumentChangeType.modified) {
            if (status == 'received') {
              NotificationService.showNotification(
                "استلام ناجح 🧺",
                "تم استلام ملابسك للطلب $orderId. هي الآن في أيدٍ أمينة لمرحلة الغسيل والكي.",
              );
            } else if (status == 'out_for_delivery') {
              NotificationService.showNotification("ملابسك في طريقها إليك 🚚", "تم تجهيز الطلب $orderId، والمندوب الآن في الطريق لتوصيل ملابسك.");
            } else if (status == 'completed') {
               NotificationService.showNotification(
                "تم التسليم ✨",
                "سعدنا بخدمتكم! تم تسليم ملابسك بنجاح للطلب رقم $orderId."
              );
            }
          }
        }
      }
    });

    // إشعارات التعاقدات (الزيارات المتعددة)
    _contractsSub = FirebaseFirestore.instance
        .collection('contracts')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        var data = change.doc.data();
        if (data == null) continue;
        Timestamp? timeStamp = (change.type == DocumentChangeType.added) 
            ? data['createdAt'] as Timestamp? 
            : data['updatedAt'] as Timestamp?;

        if (timeStamp != null && timeStamp.toDate().isAfter(_screenInitTime)) {
          String contractId = data['contractId'] ?? change.doc.id.substring(0, 5);
          String status = data['status'] ?? "";
          String clientName = data['name'] ?? "عميل";

          if (change.type == DocumentChangeType.added) {
            if (_isAdmin && (_adminType == "super" || _adminType == "cleaning") && status == 'pending') {
              NotificationService.showNotification(
                "طلب تعاقد جديد 📝", 
                "العميل $clientName يطلب اشتراكاً جديداً (رقم $contractId).",
                targetSection: 'admin'
              );
            }
          } else if (change.type == DocumentChangeType.modified) {
            if (status == 'active') {
              NotificationService.showNotification(
                "تم تفعيل اشتراكك ✨", 
                "عزيزي $clientName، عقدك رقم $contractId أصبح نشطاً الآن. نتمنى لك راحة دائمة."
              );
            }
            if (data['assignedMaid'] != null && change.type == DocumentChangeType.modified && status == 'pending') {
               NotificationService.showNotification(
                 "تحديث الفريق 👥", 
                 "تم تعيين طاقم العمل الخاص بك للعقد $contractId. سيتم التنسيق معك قريباً."
               );
            }
            if (status == 'in-progress') {
              NotificationService.showNotification(
                "بدء الزيارة الدورية 🚀", 
                "الفريق وصل الآن لبدء العمل في منزلك. راحة تتمنى لك يوماً سعيداً."
              );
            }
            if (status == 'completed') {
              NotificationService.showNotification(
                "انتهاء الزيارة ✅", 
                "تم الانتهاء من زيارة اليوم بنجاح للعقد $contractId. شكراً لاختيارك راحة."
              );
            }
          }
        }
      }
    });

    final String? currUser = FirebaseAuth.instance.currentUser?.uid;
    if (currUser != null) {
      _userSub = FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: currUser)
          .snapshots()
          .listen((snapshot) {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.modified) {
            _initData(); 
          }
        }
      });
    }
  }

  Future<void> _initData() async {
    final user = FirebaseAuth.instance.currentUser;
    try {
      final laundrySnap = await FirebaseFirestore.instance.collection('settings').doc('laundry_prices').get();
      final cleaningPricesSnap = await FirebaseFirestore.instance.collection('settings').doc('cleaning_prices').get();
      final packagesSnap = await FirebaseFirestore.instance.collection('packages').get();
      final contactSnap = await FirebaseFirestore.instance.collection('settings').doc('contact').get();

      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final userData = userDoc.data();
        final aType = userData?['adminType']; 
        
        bool isIncomplete = false;
        if (userData != null) {
          if ((userData['fullName'] ?? "").isEmpty || 
              (userData['phone'] ?? "").isEmpty || 
              (userData['region'] ?? "").isEmpty || 
              (userData['address'] ?? "").isEmpty || 
              (userData['gender'] ?? "").isEmpty) {
            isIncomplete = true;
          }
        } else {
          isIncomplete = true;
        }

        final ordersSnap = await FirebaseFirestore.instance
            .collection('bookings')
            .where('userId', isEqualTo: user.uid)
            .where('status', isEqualTo: 'completed')
            .get();

        if (mounted) {
          setState(() {
            // التحقق من أن النوع هو أحد الأنواع المسموح لها بالإدارة
            _adminType = aType;
            _isAdmin = (aType == "super" || aType == "cleaning" || aType == "laundry");
            _completedVisitsCount = ordersSnap.size;
            _isProfileIncomplete = isIncomplete;
          });
          _listenToRoleBasedOrders(); 
        }
      }

      if (mounted) {
        setState(() {
          _laundryPrices = laundrySnap.data();
          _whatsappNumber = contactSnap.data()?['whatsapp'];
          _officialSinglePrice = double.tryParse(cleaningPricesSnap.data()?['single_price']?.toString() ?? '0');
          _specialPackages = packagesSnap.docs
              .map((d) => {'id': d.id, ...d.data()})
              .where((pkg) => pkg['showIn'] == 'special')
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const CustomLoadingWidget(message: "جاري جلب البيانات...");

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _initData,
            color: Colors.blue,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildNewHero()),
                if (_isProfileIncomplete)
                  SliverToBoxAdapter(child: _buildIncompleteProfileBanner()),
                const SliverToBoxAdapter(child: SizedBox(height: 25)),
                SliverToBoxAdapter(child: _buildSectionTitle("الخدمات الاحترافية")),
                SliverToBoxAdapter(child: _buildMainServicesGrid()),
                const SliverToBoxAdapter(child: SizedBox(height: 25)),
                SliverToBoxAdapter(child: _buildSectionTitle("أقوى العروض الحصرية 🔥")),
                SliverToBoxAdapter(child: _buildSpecialOffersHorizontal()),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
          if (_whatsappNumber != null)
            Positioned(
              bottom: 110,
              left: 25,
              child: FloatingActionButton.small(
                onPressed: () async {
                  final url = Uri.parse("https://wa.me/$_whatsappNumber");
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                backgroundColor: const Color(0xFF25D366),
                child: const Icon(Icons.chat, color: Colors.white),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildIncompleteProfileBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(25, 20, 25, 0),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red[100]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "أكمل بيانات صفحة البروفايل لتواصل أسهل وخدمة أسرع ✨",
              style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
            ),
          ),
          TextButton(
            onPressed: () async {
              final result = await Navigator.push(context, MaterialPageRoute(builder: (c) => const ProfilePage()));
              if (result == true) {
                setState(() => _isProfileIncomplete = false);
                _initData();
              }
            },
            child: const Text("أكمل الآن", style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.w900)),
          )
        ],
      ),
    );
  }

  Widget _buildNewHero() {
    return SizedBox(
      height: 270, 
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 220, width: double.infinity,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/hero_bg.jpg'), 
                fit: BoxFit.cover, 
                colorFilter: ColorFilter.mode(Color.fromRGBO(0, 0, 0, 0.45), BlendMode.darken)
              ),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(60)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 70, right: 30, left: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("راحة : الحل الذكي لراحتك", style: TextStyle(color: Colors.white60, fontSize: 16)),
                      Text("للحلول التقنية و إدارة الموارد البشرية", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, fontFamily: 'Aljazeera')),
                    ],
                  ),
                  _buildNotificationBell(),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -15, left: 25, right: 25,
            child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const HandymanHubPage())),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white, 
                  borderRadius: BorderRadius.circular(30), 
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 10))]
                ),
                child: const Row(
                  children: [
                    CircleAvatar(backgroundColor: Color(0xFFEEF2FF), radius: 25, child: Icon(Icons.engineering_rounded, color: Colors.blue)),
                    SizedBox(width: 15),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text("بتفتش في شنو؟!", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                      Text("بالخريطه اطلب اقرب حرفي", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF1E293B), fontFamily: 'Aljazeera')),
                    ]),
                    Spacer(),
                    Row(children: [Text(" 100% مجاني ", style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900)), SizedBox(width: 8), Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey)])
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildNotificationBell() {
    final String? userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return const SizedBox();
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(userId).collection('notifications').where('isRead', isEqualTo: false).snapshots(),
      builder: (context, snapshot) {
        int unreadCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const NotificationsPage())), 
              icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 28)
            ),
            if (unreadCount > 0)
              Positioned(
                top: 8, right: 8, 
                child: Container(
                  padding: const EdgeInsets.all(4), 
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), 
                  child: Text(unreadCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10))
                )
              ),
          ],
        );
      },
    );
  }

  Widget _buildMainServicesGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Column(
        children: [
          // هنا يتم فحص الصلاحية بناءً على adminType
          if (_isAdmin) ...[
            _modernServiceCard(
              "لوحة الإدارة والاشراف", 
              "🛰️ تتبع الطلبات وإدارة العمليات لـ (${_adminType == 'super' ? 'الكل' : _adminType == 'cleaning' ? 'النظافة' : 'غسيل الملابس'})", 
              const Color(0xFFB71C1C), 
              const AdminCategoryPage(), 
              "🛰️"
            ),
            const SizedBox(height: 15),
          ],
          _modernServiceCard("زيارة منزلية مفردة", "✨ زيارة لمرة واحدة فقط، شاملة المعدات وعاملة مدربة لإنجاز مهامك المتعبة", const Color(0xFF673AB7), const SingleVisitPage(), "✨"),
          const SizedBox(height: 15),
          _modernServiceCard("تعاقد الزيارات المتعددة", "📦 اشتري راحتك بجدول ثابت.. توفير أكتر، مجهود أقل، وضمان نظافة بيتك بانتظام", const Color(0xFF3F51B5), const MultiVisitContractPage(), "📦"),
          if (_laundryPrices != null) ...[
            const SizedBox(height: 15),
            _modernServiceCard("غسيل الملابس (دليفري)", "🧺 استلام وتسليم :خليك دايماً قيافة.. هدومك بتجيك مكوية وجاهزة، ومن غير مشوار", const Color(0xFF2196F3), const LaundryCheckoutPage(), "🧺"),
          ],
        ],
      ),
    );
  }

  Widget _modernServiceCard(String title, String subtitle, Color color, Widget page, String iconEmoji) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => page)),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [const Color(0xFF1E293B), color], begin: Alignment.topRight, end: Alignment.bottomLeft),
          borderRadius: BorderRadius.circular(40),
          boxShadow: [BoxShadow(color: color.withAlpha(76), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, fontFamily: 'Aljazeera')),
              Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
            ])),
            Container(width: 50, height: 50, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Center(child: Text(iconEmoji, style: const TextStyle(fontSize: 24)))),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialOffersHorizontal() {
    if (_specialPackages.isEmpty) return const SizedBox();
    return SizedBox(
      height: 210, 
      child: ListView.builder(
        scrollDirection: Axis.horizontal, 
        padding: const EdgeInsets.symmetric(horizontal: 20),
        physics: const BouncingScrollPhysics(),
        itemCount: _specialPackages.length,
        itemBuilder: (context, index) {
          final pkg = _specialPackages[index];
          final int required = int.tryParse(pkg['minCompletedOrders']?.toString() ?? '0') ?? 0;
          final bool isLocked = _completedVisitsCount < required;
          final String? imageUrl = pkg['image'];

          String discountBadge = "";
          double offerPrice = double.tryParse(pkg['price']?.toString() ?? '0') ?? 0;
          if (_officialSinglePrice != null && _officialSinglePrice! > 0 && offerPrice > 0) {
            double discount = ((_officialSinglePrice! - offerPrice) / _officialSinglePrice!) * 100;
            if (discount > 0) {
              discountBadge = "${discount.toStringAsFixed(0)}%";
            }
          }

          return InkWell(
            onTap: () {
              if (isLocked) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("هذا العرض يتطلب $required زيارات مكتملة. (لديك $_completedVisitsCount)"),
                    backgroundColor: const Color(0xFF1E293B),
                  ),
                );
                return;
              }
              Navigator.push(context, MaterialPageRoute(builder: (c) => SpecialOfferCheckoutPage(packageId: pkg['id'])));
            },
            child: Container(
              width: 280, 
              margin: const EdgeInsets.only(left: 15, bottom: 10),
              decoration: BoxDecoration(
                image: imageUrl != null ? DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    isLocked ? Colors.black.withAlpha(178) : Colors.black.withAlpha(114), 
                    BlendMode.darken
                  ),
                ) : null,
                gradient: imageUrl == null ? LinearGradient(
                  colors: isLocked 
                      ? [Colors.grey.shade600, Colors.black87] 
                      : [const Color(0xFF3B82F6), const Color(0xFF1E40AF)], 
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ) : null, 
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: isLocked ? Colors.black12 : Colors.blue.withAlpha(76),
                    blurRadius: 10,
                    offset: const Offset(0, 5)
                  )
                ]
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                    children: [
                      Expanded(
                        child: Text(pkg['name'] ?? "عرض حصري", 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Aljazeera'),
                          maxLines: 1, overflow: TextOverflow.ellipsis
                        ),
                      ), 
                      if (discountBadge.isNotEmpty && !isLocked)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(12)),
                          child: Text("خصم $discountBadge", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      else
                        Icon(isLocked ? Icons.lock_outline : Icons.local_offer, color: Colors.white, size: 20)
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    pkg['description'] ?? "",
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  if (!isLocked && offerPrice > 0)
                    Text("السعر الحالي: ${offerPrice.toStringAsFixed(0)} ج.س", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    isLocked ? "🏆 يتطلب $required زيارة لفتحه" : "احجز الآن واستفد من الخصم", 
                    style: TextStyle(color: isLocked ? Colors.white70 : Colors.white, fontSize: 12, fontWeight: isLocked ? FontWeight.normal : FontWeight.bold)
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      height: 80, margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(35)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround, 
        children: [
          _navItem("الرئيسية", Icons.home_rounded, true, null), 
          _navItem("طلباتي", Icons.receipt_long_rounded, false, const MyBookingsPage()), 
          _navItem("العروض", Icons.local_offer_rounded, false, const OffersPage()), 
          _navItem("حسابي", Icons.person_rounded, false, const ProfilePage(), isWarning: _isProfileIncomplete)
        ]
      ),
    );
  }

  Widget _navItem(String label, IconData icon, bool active, Widget? page, {bool isWarning = false}) {
    return InkWell(
      onTap: () async {
        if (page != null) {
          final result = await Navigator.push(context, MaterialPageRoute(builder: (c) => page));
          if (result == true) {
            setState(() => _isProfileIncomplete = false);
            _initData();
          }
        }
      }, 
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, 
        children: [
          Stack(
            children: [
              Icon(icon, color: active ? Colors.blueAccent : Colors.white38, size: 26),
              if (isWarning)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 8, minHeight: 8),
                  ),
                )
            ],
          ), 
          Text(label, style: TextStyle(color: active ? Colors.white : Colors.white38, fontSize: 10))
        ]
      )
    );
  }

  Widget _buildSectionTitle(String title) => Padding(padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, fontFamily: 'Aljazeera')));
}