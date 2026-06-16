import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

// استيراد الصفحات المطلوبة للتنقل
import 'single_visit_page.dart'; 
import 'multi_visit_contract_page.dart'; 
import 'laundry_checkout_page.dart';
import 'special_offer_checkout_page.dart';

class OffersPage extends StatefulWidget {
  const OffersPage({super.key});

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  bool _isLoading = true;
  bool _isNavigating = false;
  List<Map<String, dynamic>> _packages = [];
  Map<String, dynamic>? _laundryPrices;
  int _completedVisitsCount = 0;
  StreamSubscription? _pkgSubscription;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'completed')
          .get();
      
      if (mounted) {
        setState(() => _completedVisitsCount = snap.size);
      }
    }

    _pkgSubscription = FirebaseFirestore.instance
        .collection('packages')
        .orderBy('price', descending: false)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _packages = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
          _isLoading = false;
        });
      }
    });

    final laundryDoc = await FirebaseFirestore.instance.collection('settings').doc('laundry_prices').get();
    if (laundryDoc.exists && mounted) {
      setState(() => _laundryPrices = laundryDoc.data());
    }
  }

  @override
  void dispose() {
    _pkgSubscription?.cancel();
    super.dispose();
  }

  // تعديل معالج الحجز لينقل للصفحة المطلوبة بنفس منطق main.dart
  void _handleBooking(Map<String, dynamic> pkg) {
    final required = int.tryParse(pkg['minCompletedOrders']?.toString() ?? '0') ?? 0;
    final bool isLocked = pkg['showIn'] != 'main' && _completedVisitsCount < required;

    if (isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("هذا العرض يتطلب $required زيارات مكتملة. (لديك $_completedVisitsCount)"),
          backgroundColor: const Color(0xFF1E293B),
        ),
      );
      return;
    }

    setState(() => _isNavigating = true);
    
    Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() => _isNavigating = false);
        // الانتقال لصفحة دفع العروض الخاصة مع إرسال الـ ID
        Navigator.push(
          context, 
          MaterialPageRoute(builder: (c) => SpecialOfferCheckoutPage(packageId: pkg['id']))
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 40, height: 40,
                child: CircularProgressIndicator(color: Color(0xFF1E293B), strokeWidth: 5),
              ),
              const SizedBox(height: 20),
              Text("جاري تحضير قائمة الخدمات...", 
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w900, color: const Color(0xFF1E293B).withAlpha(128), fontStyle: FontStyle.italic)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildHeader(),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    ..._packages.map((pkg) => _buildPackageCard(pkg)),
                    
                    const SizedBox(height: 25),
                    
                    _buildSectionCard(
                      title: "زيارات متعددة",
                      subtitle: "اشتراكات شهرية مرنة تناسب احتياجك",
                      icon: "📦",
                      colors: [const Color(0xFF1E293B), const Color(0xFF3F51B5)],
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const MultiVisitContractPage())),
                    ),
                    
                    const SizedBox(height: 15),
                    
                    _buildSectionCard(
                      title: "زيارات منفردة",
                      subtitle: "خدمة سريعة ومتميزة عند الطلب",
                      icon: "✨",
                      colors: [const Color(0xFF1E293B), const Color(0xFF673AB7)],
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const SingleVisitPage())),
                    ),

                    if (_laundryPrices != null) ...[
                      const SizedBox(height: 15),
                      _buildSectionCard(
                        title: "غسيل دليفري",
                        subtitle: "نستلم ملابسك ونعيدها لك",
                        icon: "🧺",
                        colors: [const Color(0xFF1E293B), const Color(0xFF2196F3)],
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const LaundryCheckoutPage())),
                      ),
                    ],
                  ]),
                ),
              ),
            ],
          ),
          
          if (_isNavigating)
            Container(
              color: Colors.white.withAlpha(153),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF1E293B)),
                    SizedBox(height: 15),
                    Text("جاري تأمين الحجز...", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ),

          _buildHomeButton(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.only(top: 80, bottom: 50, right: 30, left: 30),
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          borderRadius: BorderRadius.only(bottomLeft: Radius.circular(60), bottomRight: Radius.circular(60)),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, fontFamily: 'Cairo', fontStyle: FontStyle.italic),
                children: [
                  TextSpan(text: "قائمة ", style: TextStyle(color: Colors.white)),
                  TextSpan(text: "الخدمات", style: TextStyle(color: Colors.blueAccent)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text("استكشف باقاتنا العادية والحصرية", 
              style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageCard(Map<String, dynamic> pkg) {
    final required = int.tryParse(pkg['minCompletedOrders']?.toString() ?? '0') ?? 0;
    final bool isLocked = pkg['showIn'] != 'main' && _completedVisitsCount < required;

    return GestureDetector(
      onTap: () => _handleBooking(pkg),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: isLocked ? Colors.grey[100]! : Colors.white),
          boxShadow: [BoxShadow(color: Colors.blueGrey.withAlpha(12), blurRadius: 15, offset: const Offset(0, 10))],
        ),
        child: Row(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Image.network(
                    pkg['image'] ?? "https://img.freepik.com/free-vector/cleaning-service-logo-design_23-2148525287.jpg",
                    width: 85, height: 85, fit: BoxFit.cover,
                  ),
                ),
                if (isLocked)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(color: const Color(0xFF1E293B).withAlpha(153), borderRadius: BorderRadius.circular(30)),
                      child: const Icon(Icons.lock, color: Colors.white, size: 24),
                    ),
                  )
                else
                  Positioned(
                    top: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: pkg['timePeriod'] == 'morning' ? Colors.amber[700] : Colors.indigo[800],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(pkg['timePeriod'] == 'morning' ? '☀️ صباحي' : '🌙 مسائي', 
                        style: const TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pkg['name'] ?? "باقة غير معروفة", 
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1E293B), fontStyle: FontStyle.italic)),
                  const SizedBox(height: 5),
                  if (isLocked)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("🏆 باقة متميزة", style: TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
                        Text("تحتاج $required زيارة (رصيدك: $_completedVisitsCount)", style: const TextStyle(color: Colors.grey, fontSize: 7, fontWeight: FontWeight.bold)),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.blue[100]!)),
                          child: Text(pkg['category'] == 'monthly' ? 'اشتراك شهري' : '⏱️ ${pkg['hours'] ?? 4} ساعات',
                              style: const TextStyle(color: Colors.blue, fontSize: 8, fontWeight: FontWeight.w900)),
                        ),
                        const SizedBox(width: 10),
                        Text("${pkg['price']} SDG", style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1E293B), fontSize: 14)),
                      ],
                    ),
                ],
              ),
            ),
            if (!isLocked)
              const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF1E293B)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required String subtitle, required String icon, required List<Color> colors, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [BoxShadow(color: colors.last.withAlpha(77), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                  child: const Text("باقة توفير", style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
                ),
                const SizedBox(height: 8),
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
              ],
            ),
            Container(
              width: 55, height: 55,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
              child: Center(child: Text(icon, style: const TextStyle(fontSize: 26))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeButton() {
    return Positioned(
      bottom: 30,
      left: 0, right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 15),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withAlpha(242),
              borderRadius: BorderRadius.circular(50),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(77), blurRadius: 20)],
              border: Border.all(color: Colors.white12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("🏠", style: TextStyle(fontSize: 20)),
                SizedBox(width: 12),
                Text("الرئيسية", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
