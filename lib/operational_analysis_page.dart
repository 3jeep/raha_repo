import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:rxdart/rxdart.dart'; // ستحتاج لإضافة rxdart في pubspec.yaml لدمج التيارات بسهولة

class OperationalAnalysisPage extends StatefulWidget {
  const OperationalAnalysisPage({super.key});

  @override
  State<OperationalAnalysisPage> createState() => _OperationalAnalysisPageState();
}

class _OperationalAnalysisPageState extends State<OperationalAnalysisPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // دمج التيارات لضمان تحديث الواجهة مرة واحدة عند تغيير أي بيانات
  Stream<Map<String, List<QueryDocumentSnapshot>>> _getCombinedData() {
    return CombineLatestStream.combine2(
      _db.collection('bookings').snapshots(),
      _db.collection('laundry_orders').snapshots(),
      (QuerySnapshot b, QuerySnapshot l) => {
        'bookings': b.docs,
        'laundry': l.docs,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text("لوحة القيادة والتحليل الشامل",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
          centerTitle: true,
          backgroundColor: const Color(0xFF1E293B),
          elevation: 0,
        ),
        body: StreamBuilder<Map<String, List<QueryDocumentSnapshot>>>(
          stream: _getCombinedData(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text("حدث خطأ في تحميل البيانات: ${snapshot.error}"));
            }

            final bookingDocs = snapshot.data?['bookings'] ?? [];
            final laundryDocs = snapshot.data?['laundry'] ?? [];

            // --- الحسابات المالية والتشغيلية ---
            
            // 1. قطاع النظافة (زيارات مفردة مكتملة فقط)
            var compSingles = bookingDocs.where((d) {
              final data = d.data() as Map<String, dynamic>;
              // التعديل: التأكد من أن الحالة مكتملة والنوع زيارة مفردة
              return data['status'] == 'completed' && data['category'] == 'single_visit';
            }).toList();
            
            double singleRevenue = compSingles.fold(0, (total, d) => total + (double.tryParse(d['price']?.toString() ?? '0') ?? 0));

            // 2. قطاع المغسلة
            var compLaundry = laundryDocs.where((d) => d['status'] == 'completed').toList();
            double laundryRevenue = compLaundry.fold(0, (total, d) => total + (double.tryParse(d['totalPrice']?.toString() ?? '0') ?? 0));
            int totalLaundryPieces = compLaundry.fold(0, (total, d) => total + (int.tryParse(d['pieces']?.toString() ?? '0') ?? 0));
            
            // حساب التوقيعات بطريقة آمنة
            int signedOrders = compLaundry.where((d) {
              final data = d.data() as Map<String, dynamic>;
              return data.containsKey('customerSignature') && data['customerSignature'] != null;
            }).length;

            // 3. العروض الخاصة المكتملة
            var compSpecial = bookingDocs.where((d) {
              final data = d.data() as Map<String, dynamic>;
              return data['status'] == 'completed' && data['category'] == 'special_offer';
            }).toList();
            double specialRevenue = compSpecial.fold(0, (total, d) => total + (double.tryParse(d['price']?.toString() ?? '0') ?? 0));

            double totalGrandRevenue = singleRevenue + laundryRevenue + specialRevenue;
            int totalCompletedOps = compSingles.length + compLaundry.length + compSpecial.length;

            return ListView( // استخدام ListView بدلاً من SingleChildScrollView لتجنب مشاكل الارتفاع
              padding: const EdgeInsets.all(20),
              children: [
                _buildHeaderSection(totalCompletedOps, totalGrandRevenue),
                const SizedBox(height: 25),
                
                const Text("تحليل قطاع المغسلة والخدمات اللوجستية", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 15),
                
                _buildAnalysisCard(
                  "إنتاجية المغسلة", 
                  "إجمالي القطع التي تم تنظيفها وتسليمها", 
                  "$totalLaundryPieces قطعة", 
                  Colors.blue
                ),

                _buildAnalysisCard(
                  "جودة التوثيق الرقمي", 
                  "نسبة الطلبات المسلمة بتوقيع معتمد", 
                  "${compLaundry.isEmpty ? 0 : ((signedOrders / compLaundry.length) * 100).toStringAsFixed(1)}%", 
                  Colors.teal
                ),

                const SizedBox(height: 25),
                const Text("مقارنة الأداء التشغيلي (عدد العمليات)", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 15),
                
                Row(
                  children: [
                    Expanded(child: _miniStatCard("زيارات", compSingles.length.toString(), Colors.orange)),
                    const SizedBox(width: 10),
                    Expanded(child: _miniStatCard("عروض", compSpecial.length.toString(), Colors.deepPurple)),
                    const SizedBox(width: 10),
                    Expanded(child: _miniStatCard("مغسلة", compLaundry.length.toString(), Colors.blue)),
                  ],
                ),
                
                const SizedBox(height: 25),
                _buildAnalysisCard(
                  "الحالة المالية (المغسلة)", 
                  "صافي الدخل من طلبات المغسلة فقط", 
                  "${laundryRevenue.toStringAsFixed(0)} ج.س", 
                  Colors.green
                ),
                
                _buildAnalysisCard(
                  "إيرادات الخدمات المنزلية", 
                  "دخل الزيارات المفردة والعروض الخاصة", 
                  "${(singleRevenue + specialRevenue).toStringAsFixed(0)} ج.س", 
                  Colors.orange
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // --- المكونات الرسومية (UI Widgets) ---

  Widget _buildHeaderSection(int totalOps, double revenue) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1E293B), Color(0xFF334155)]
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(26), blurRadius: 20, offset: const Offset(0, 10))]
      ),
      child: Column(
        children: [
          const Text("إجمالي الإيرادات المجمعة", style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 10),
          Text("${revenue.toStringAsFixed(0)} ج.س", 
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
          const Divider(color: Colors.white10, height: 30),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withAlpha(13), borderRadius: BorderRadius.circular(15)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                const SizedBox(width: 8),
                Text("تم إنجاز $totalOps طلب بنجاح", 
                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _miniStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.withAlpha(13)),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10)]
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAnalysisCard(String title, String desc, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.withAlpha(13)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(15)),
            child: Icon(Icons.analytics_outlined, color: color, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
