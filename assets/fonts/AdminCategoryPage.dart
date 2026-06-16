import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl; 
import 'Monthly_contracts_page.dart'; 
import 'SingleVisitsPage.dart'; 
import 'LaundryOrdersPage.dart'; 
import 'dart:async';

class AdminCategoryPage extends StatefulWidget {
  const AdminCategoryPage({super.key});

  @override
  State<AdminCategoryPage> createState() => _AdminCategoryPageState();
}

class _AdminCategoryPageState extends State<AdminCategoryPage> {
  String adminRole = "loading"; 
  String adminName = "المدير"; 
  final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _fetchAdminData();
  }

  Future<void> _fetchAdminData() async {
    try {
      DocumentSnapshot userDoc = await _db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        var data = userDoc.data() as Map<String, dynamic>;
        setState(() {
          adminRole = data['adminType'] ?? "staff"; 
          adminName = data['name'] ?? "المدير";
        });
      } else {
        setState(() => adminRole = "unauthorized");
      }
    } catch (e) {
      setState(() => adminRole = "error");
    }
  }

  Stream<List<QueryDocumentSnapshot>> _getCombinedStream() {
    Stream<QuerySnapshot> s1 = _db.collection('bookings').snapshots();
    Stream<QuerySnapshot> s2 = _db.collection('contracts').snapshots();
    Stream<QuerySnapshot> s3 = _db.collection('laundry_orders').snapshots();

    return StreamZip([s1, s2, s3]).map((snapshots) {
      List<QueryDocumentSnapshot> allDocs = [];
      for (var snap in snapshots) {
        allDocs.addAll(snap.docs);
      }
      return allDocs;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (adminRole == "loading") {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC), 
        appBar: AppBar(
          elevation: 0,
          backgroundColor: const Color(0xFF1E293B),
          title: const Text("لوحة الإدارة الشاملة 🛰️", 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, fontFamily: 'Ar.ttf')),
          centerTitle: true,
        ),
        body: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            // 1. كرت الترحيب الذكي
            Padding(
              padding: const EdgeInsets.all(20),
              child: _buildSmartWelcomeCard(),
            ),

            // 2. أزرار الوصول السريع
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  if (adminRole == "super" || adminRole == "cleaning")
                    _menuCard("العقود الشهرية", "🗓️", Colors.blue, const MonthlyContractsPage()),
                  if (adminRole == "super" || adminRole == "cleaning")
                    _menuCard("الزيارات العابرة", "🚀", Colors.orange, SingleVisitsPage(adminType: adminRole)),
                  if (adminRole == "super" || adminRole == "laundry")
                    _menuCard("إدارة طلبات الغسيل", "🧼", Colors.teal, const LaundryOrdersPage()),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // 3. قسم المالية
            if (adminRole == "super") ...[
              _buildSectionHeader("الأداء المالي 💰", Colors.green, Icons.account_balance_wallet_rounded),
              _buildFinancialReportSection(),
            ],

            // 4. التحليل التشغيلي
            _buildSectionHeader("التحليل التشغيلي 📊", Colors.blue, Icons.analytics_rounded),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildUnifiedDashboardGrid(),
            ),

            // 5. سجل التميز
            _buildSectionHeader("نجوم الخدمة 🏆", Colors.amber, Icons.auto_awesome_rounded),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("العاملات الأعلى تقييماً من قبل العملاء", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 15),
                  _buildTopMaidsList(),
                ],
              ),
            ),

            const SizedBox(height: 30),
            const Center(
              child: Opacity(
                opacity: 0.3,
                child: Text("نظام إدارة العمليات الشامل v2.0", style: TextStyle(fontSize: 10, color: Colors.blueGrey)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 25, 20, 15),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF1E293B), fontFamily: 'Ar.ttf')),
        ],
      ),
    );
  }

  Widget _buildFinancialReportSection() {
    String today = intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
    String currentMonth = intl.DateFormat('yyyy-MM').format(DateTime.now());

    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: _getCombinedStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(20), child: LinearProgressIndicator());
        
        double dailyTotal = 0, monthTotal = 0, uncollected = 0;

        for (var doc in snapshot.data!) {
          var data = doc.data() as Map<String, dynamic>;
          double price = double.tryParse(data['totalPrice']?.toString() ?? '0') ?? 0;
          String date = data['startDate'] ?? data['createdAt'] ?? "";
          String status = data['status'] ?? "";

          if (date.contains(today) && status == 'completed') dailyTotal += price;
          if (date.startsWith(currentMonth) && status == 'completed') monthTotal += price;
          if (status == 'pending' || status == 'in-progress') uncollected += price;
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(25),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))]
          ),
          child: Column(
            children: [
              _financeItem("إيرادات اليوم المكتملة", dailyTotal, Colors.green, Icons.trending_up),
              const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: Color(0xFFF1F5F9))),
              _financeItem("إجمالي إيرادات الشهر", monthTotal, Colors.blue, Icons.calendar_month),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                    const SizedBox(width: 10),
                    const Text("مبالغ في الميدان:", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                    const Spacer(),
                    Text("${uncollected.toStringAsFixed(0)} ج.س", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 14)),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _financeItem(String title, double value, Color color, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontSize: 13, color: Colors.black87)),
        const Spacer(),
        Text("${value.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(width: 4),
        const Text("ج.س", style: TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildSmartWelcomeCard() {
    String todayStr = intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: _getCombinedStream(),
      builder: (context, snapshot) {
        int totalAll = 0, completedToday = 0, activeToday = 0;
        double progressVal = 0.0;
        if (snapshot.hasData) {
          var docs = snapshot.data!;
          totalAll = docs.length;
          var todayDocs = docs.where((d) {
            var map = d.data() as Map;
            return (map['startDate'] == todayStr || map['createdAt']?.toString().contains(todayStr) == true);
          }).toList();
          activeToday = todayDocs.length;
          completedToday = todayDocs.where((d) => (d.data() as Map)['status'] == 'completed').length;
          if (activeToday > 0) progressVal = completedToday / activeToday;
        }
        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF1E293B), Color(0xFF475569)], begin: Alignment.topRight, end: Alignment.bottomLeft),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: Colors.blueGrey.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 10))]
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("مرحباً بك،", style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text("$adminName 👋", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20, fontFamily: 'Ar.ttf')),
                    ],
                  ),
                  _circularProgressIndicator(progressVal),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _miniStat(totalAll.toString(), "إجمالي الطلبات"),
                  Container(width: 1, height: 30, color: Colors.white12, margin: const EdgeInsets.symmetric(horizontal: 15)),
                  _miniStat(activeToday.toString(), "مهام اليوم"),
                ],
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(value: progressVal, minHeight: 8, backgroundColor: Colors.white10, valueColor: const AlwaysStoppedAnimation(Colors.greenAccent)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _circularProgressIndicator(double val) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(width: 50, height: 50, child: CircularProgressIndicator(value: val, strokeWidth: 5, backgroundColor: Colors.white10, valueColor: const AlwaysStoppedAnimation(Colors.greenAccent))),
        Text("${(val * 100).toInt()}%", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _miniStat(String val, String label) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
    ]);
  }

  Widget _buildUnifiedDashboardGrid() {
    String today = intl.DateFormat('yyyy-MM-dd').format(DateTime.now());
    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: _getCombinedStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        var docs = snapshot.data!;
        int single = docs.where((d) => d.reference.parent.id == 'bookings' && (d.data() as Map)['startDate'] == today).length;
        int monthly = docs.where((d) => d.reference.parent.id == 'contracts' && (d.data() as Map)['startDate'] == today).length;
        int inProgress = docs.where((d) => (d.data() as Map)['status'] == 'in-progress').length;
        int pending = docs.where((d) => (d.data() as Map)['status'] == 'pending').length;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _statTile("زيارات مفردة", single.toString(), Colors.orange, Icons.bolt_rounded),
            _statTile("عقود اليوم", monthly.toString(), Colors.blue, Icons.calendar_today_rounded),
            _statTile("طلبات معلقة", pending.toString(), Colors.redAccent, Icons.hourglass_top_rounded),
            _statTile("جاري التنفيذ", inProgress.toString(), Colors.green, Icons.play_circle_fill_rounded),
          ],
        );
      },
    );
  }

  Widget _statTile(String label, String value, Color color, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(22), 
        boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Stack(
        children: [
          Positioned(right: -10, bottom: -10, child: Icon(icon, color: color.withOpacity(0.05), size: 60)),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 5),
                Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
                Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54, fontFamily: 'Ar.ttf')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuCard(String title, String emoji, Color col, Widget destination) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        leading: CircleAvatar(backgroundColor: col.withOpacity(0.1), child: Text(emoji, style: const TextStyle(fontSize: 18))),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B), fontFamily: 'Ar.ttf')),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => destination)),
      ),
    );
  }

  Widget _buildTopMaidsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('bookings').where('status', isEqualTo: 'completed').where('rating', isEqualTo: 'ممتاز').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        Map<String, int> performance = {};
        for (var doc in snapshot.data!.docs) {
          String maid = doc['assignedMaid'] ?? "";
          if (maid.isNotEmpty) performance[maid] = (performance[maid] ?? 0) + 1;
        }
        var sorted = (performance.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).toList();
        return Column(
          children: sorted.map((e) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade100)),
            child: Row(
              children: [
                const CircleAvatar(radius: 15, backgroundColor: Color(0xFFF1F5F9), child: Icon(Icons.person, size: 15, color: Colors.blueGrey)),
                const SizedBox(width: 12),
                Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text("${e.value} ⭐ تميز", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 10, fontFamily: 'Ar.ttf')),
                ),
              ],
            ),
          )).toList(),
        );
      },
    );
  }
}

class StreamZip<T> extends Stream<List<T>> {
  final Iterable<Stream<T>> streams;
  StreamZip(this.streams);
  @override
  StreamSubscription<List<T>> listen(void Function(List<T> event)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final subscriptions = <StreamSubscription<T>>[];
    final values = <T?>[];
    final isDone = <bool>[];
    final controller = StreamController<List<T>>(sync: true);
    void update() { if (values.every((v) => v != null)) controller.add(List<T>.from(values!)); }
    int i = 0;
    for (var stream in streams) {
      final index = i++;
      values.add(null);
      isDone.add(false);
      subscriptions.add(stream.listen((data) { values[index] = data; update(); }, onError: controller.addError, onDone: () {
        isDone[index] = true;
        if (isDone.every((d) => d)) controller.close();
      }, cancelOnError: cancelOnError));
    }
    controller.onCancel = () { for (var s in subscriptions) s.cancel(); };
    return controller.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}
