import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// استيراد الصفحات المطلوبة
import 'laundry_orders_page.dart';
import 'monthly_contracts_page.dart';
import 'single_visits_page.dart';
import 'operational_analysis_page.dart';

class AdminCategoryPage extends StatefulWidget {
  const AdminCategoryPage({super.key});

  @override
  State<AdminCategoryPage> createState() => _AdminCategoryPageState();
}

class _AdminCategoryPageState extends State<AdminCategoryPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String adminRole = "loading";
  String adminName = "المدير";
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";

  @override
  void initState() {
    super.initState();
    _fetchAdminData();
  }

  Future<void> _fetchAdminData() async {
    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            adminRole = data['adminType'] ?? "staff";
            adminName = data['name'] ?? "المدير";
          });
        }
      } else {
        if (mounted) setState(() => adminRole = "unauthorized");
      }
    } catch (e) {
      if (mounted) setState(() => adminRole = "error");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (adminRole == "loading") {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xffF8FAFC),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          elevation: 0,
          centerTitle: true,
          title: const Text(
            "لوحة الإدارة 🛰️",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 15),
                // كارت الترحيب
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildSmartWelcomeCard(),
                ),
                
                const SizedBox(height: 25),
                _buildSectionHeader("أقسام الإدارة والتحليل", Icons.category_rounded, Colors.blueGrey),
                
                // أزرار التنقل الأساسية
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      if (adminRole == "super")
                        _menuCard(
                          "مركز التحليل والبيانات",
                          "📊",
                          Colors.indigo,
                          const OperationalAnalysisPage(),
                          isSpecial: true,
                        ),

                      if (adminRole == "super" || adminRole == "cleaning")
                        _menuCard("العقود الشهرية", "🗓️", Colors.blue, const MonthlyContractsPage()),

                      if (adminRole == "super" || adminRole == "cleaning")
                        _menuCard("الزيارات العابرة", "🚀", Colors.orange, SingleVisitsPage(adminType: adminRole)),

                      if (adminRole == "super" || adminRole == "laundry")
                        _menuCard("إدارة طلبات الغسيل", "🧼", Colors.teal, const LaundryOrdersPage()),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                _buildSectionHeader("نجوم الخدمة (الأعلى تقييماً) 🏆", Icons.star_rounded, Colors.amber[700]!),

                // قائمة أعلى العاملات تقييماً
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildTopPerformersList(),
                ),

                const SizedBox(height: 40),
                const Center(
                  child: Opacity(
                    opacity: 0.4,
                    child: Text("نظام إدارة العمليات v2.0", style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 15),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        ],
      ),
    );
  }

  // ويدجت استعراض أعلى العاملات
  Widget _buildTopPerformersList() {
    return StreamBuilder<QuerySnapshot>(
      // جلب الزيارات المكتملة فقط التي حصلت على تقييم "ممتاز"
      stream: _db.collection('bookings')
          .where('status', isEqualTo: 'completed')
          .where('rating', isEqualTo: 'ممتاز')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        Map<String, int> performanceMap = {};

        for (var doc in snapshot.data!.docs) {
          String name = doc['assignedMaid'] ?? "غير معروف";
          if (name != "غير معروف") {
            performanceMap[name] = (performanceMap[name] ?? 0) + 1;
          }
        }

        // ترتيب العاملات حسب عدد التقييمات الممتازة
        var sortedList = performanceMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        if (sortedList.isEmpty) {
          return const Center(
            child: Text("لا توجد تقييمات ممتازة مسجلة حالياً", 
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          );
        }

        return Column(
          children: sortedList.take(3).map((entry) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10)],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.amber.withAlpha(25),
                    child: const Icon(Icons.person, color: Colors.amber),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text("${entry.value} تميز", 
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildSmartWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF475569)]),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("مرحباً بك مجدداً", style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 5),
                Text("$adminName 👋", 
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 21)),
              ],
            ),
          ),
          const Icon(Icons.admin_panel_settings, color: Colors.white, size: 40),
        ],
      ),
    );
  }

  Widget _menuCard(String title, String emoji, Color color, Widget destination, {bool isSpecial = false}) {
    return Card(
      elevation: isSpecial ? 4 : 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: isSpecial ? BorderSide(color: color.withAlpha(128), width: 1) : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(25),
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSpecial ? color : Colors.black87,
          ),
        ),
        trailing: Icon(Icons.chevron_left_rounded, color: isSpecial ? color : Colors.grey),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => destination));
        },
      ),
    );
  }
}
