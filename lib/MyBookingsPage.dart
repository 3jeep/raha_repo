import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui' as ui;

// استيراد الخدمات الخاصة بالمشروع
import 'notification_service.dart'; 

class MyBookingsPage extends StatefulWidget {
  const MyBookingsPage({super.key});

  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage> {
  String _activeFilter = "all";
  bool _isLoading = true;
  List<Map<String, dynamic>> _allOrders = [];
  StreamSubscription? _subscription;
  
  String _supportWhatsApp = ""; 
  bool _isInitialLoad = true;

  @override
  void initState() {
    super.initState();
    _fetchContactSettings(); 
    _listenToAllOrders();
  }

  Future<void> _fetchContactSettings() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('contact').get();
      if (doc.exists && doc.data() != null) {
        setState(() {
          _supportWhatsApp = doc.data()!['whatsapp'] ?? "";
        });
      }
    } catch (e) {
      debugPrint("Error fetching contact settings: $e");
    }
  }

  // الدالة المصححة لجلب البيانات من كولكشن العقود الجديد
  void _listenToAllOrders() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _subscription = FirebaseFirestore.instance
        .collection('bookings')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) async {
      
      try {
        // جلب البيانات من 3 مصادر مختلفة: الزيارات، الغسيل، والعقود
        final results = await Future.wait([
          FirebaseFirestore.instance.collection('bookings').where('userId', isEqualTo: user.uid).get(),
          FirebaseFirestore.instance.collection('laundry_orders').where('userId', isEqualTo: user.uid).get(),
          FirebaseFirestore.instance.collection('contracts').where('userId', isEqualTo: user.uid).get(),
        ]);

        List<Map<String, dynamic>> temp = [];
        int completedCount = 0;

        // 1. معالجة الزيارات المفردة
        for (var doc in results[0].docs) {
          var d = doc.data();
          temp.add({'id': doc.id, ...d, 'source': 'booking'});
          if (d['status'] == 'completed') completedCount++;
        }
        
        // 2. معالجة طلبات الغسيل
        for (var doc in results[1].docs) {
          var d = doc.data();
          temp.add({'id': doc.id, ...d, 'source': 'laundry'});
          if (d['status'] == 'delivered' || d['status'] == 'completed') completedCount++;
        }

        // 3. معالجة العقود (التصحيح هنا)
        for (var doc in results[2].docs) {
          var d = doc.data();
          temp.add({
            'id': doc.id, 
            ...d, 
            'source': 'contract',
            'packageName': d['contractId'] ?? "عقد شهري" // استخدام رقم العقد كاسم للحزمة
          });
          if (d['status'] == 'contract_finished' || d['status'] == 'completed') completedCount++;
        }

        _checkNewOffers(completedCount);

        // الترتيب حسب تاريخ الإنشاء
        temp.sort((a, b) {
          Timestamp tA = a['createdAt'] ?? Timestamp(0, 0);
          Timestamp tB = b['createdAt'] ?? Timestamp(0, 0);
          return tB.compareTo(tA);
        });

        if (mounted) {
          setState(() {
            _allOrders = temp;
            _isLoading = false;
            _isInitialLoad = false;
          });
        }
      } catch (e) {
        debugPrint("Error merging data: $e");
      }
    });
  }

  void _checkNewOffers(int count) {
    if (!_isInitialLoad && count > 0 && (count % 5 == 0)) {
       NotificationService.showNotification(
         "مبروك! فتحت عرضاً جديداً 🎁", 
         "بسبب وصولك لـ $count طلب مكتمل، تفقد قسم الهدايا الآن."
       );
    }
  }

  Future<void> _cancelOrder(String id, String source) async {
    final collection = source == 'laundry' ? 'laundry_orders' : (source == 'contract' ? 'contracts' : 'bookings');
    try {
      await FirebaseFirestore.instance.collection(collection).doc(id).update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم إلغاء الطلب بنجاح")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("عذراً، تعذر إلغاء الطلب")));
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredOrders {
    return _allOrders.where((o) {
      final status = o['status'] ?? "";
      final isDone = ["completed", "completed_for_today", "contract_finished", "delivered"].contains(status);
      if (_activeFilter == "all") return true;
      if (_activeFilter == "completed") return isDone;
      if (_activeFilter == "active") return !isDone && status != "cancelled";
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildFilterBar()),
            _isLoading 
              ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              : _filteredOrders.isEmpty 
                ? const SliverFillRemaining(child: Center(child: Text("لا توجد طلبات لعرضها حالياً", style: TextStyle(color: Colors.grey))))
                : SliverPadding(
                    padding: const EdgeInsets.all(20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildOrderCard(_filteredOrders[index]),
                        childCount: _filteredOrders.length,
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 60, bottom: 30, right: 30, left: 30),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(50), bottomRight: Radius.circular(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text("سجل طلباتي", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          Text("نظام إدارة خدمات راحة", style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final filters = [{'id': 'all', 'label': 'الكل'}, {'id': 'active', 'label': 'قيد التنفيذ'}, {'id': 'completed', 'label': 'مكتملة'}];
    return Container(
      height: 80,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        children: filters.map((f) {
          bool isSelected = _activeFilter == f['id'];
          return GestureDetector(
            onTap: () => setState(() => _activeFilter = f['id']!),
            child: Container(
              margin: const EdgeInsets.only(left: 10),
              padding: const EdgeInsets.symmetric(horizontal: 25),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue[600] : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: isSelected ? [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10)] : [],
              ),
              child: Center(child: Text(f['label']!, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 12, fontWeight: FontWeight.w900))),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final bool isContract = order['source'] == 'contract';
    final bool isLaundry = order['source'] == 'laundry';
    final status = order['status'] ?? "";
    final bool isFullDone = ["completed", "contract_finished", "delivered"].contains(status);
    final bool isCancelled = status == "cancelled";
    
    final bool canBeCancelled = status == "pending" || status == "active_pending";

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _badge(isContract ? "🗓️ عقد شهري" : (isLaundry ? "🧺 مغسلة" : "✨ زيارة"), Colors.blue[50]!, Colors.blue),
              _badge(isCancelled ? "ملغي" : isFullDone ? "مكتمل" : "نشط", isCancelled ? Colors.red[50]! : isFullDone ? Colors.green[50]! : Colors.orange[50]!, isCancelled ? Colors.red : isFullDone ? Colors.green : Colors.orange),
            ],
          ),
          const SizedBox(height: 15),
          Text(order['packageName'] ?? (isLaundry ? "طلب غسيل ملابس" : "خدمة تنظيف منزلي"), 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          
          _infoRow(Icons.map_outlined, "المنطقة:", order['region'] ?? "غير محدد"),

          if (isContract) ...[
            _infoRow(Icons.calendar_today, "أيام الحضور:", (order['selectedDays'] as List?)?.join(" - ") ?? "غير محدد"),
            _infoRow(Icons.person, "الموظفة المعينة:", order['assignedMaid'] ?? "جاري التعيين"),
            _infoRow(Icons.local_shipping, "السائق:", order['driverName'] ?? "جاري التنسيق"),
          ],

          if (isLaundry) ...[
            _infoRow(Icons.local_shipping, "الموصل:", order['deliveredByDriver'] ?? "جاري التنسيق"),
            _infoRow(Icons.inventory_2, "الكمية:", "${order['pieces'] ?? 0} قطعة"),
          ],

          if (!isLaundry && !isContract) ...[
             _infoRow(Icons.groups, "عدد الموظفات:", "${order['maidsCount'] ?? 1}"),
             _infoRow(Icons.person, "الموظفة المعينة:", order['assignedMaid'] ?? "قيد التعيين"),
          ],
          
          const Divider(height: 30),
          
          if (isLaundry && order['customerSignature'] != null) ...[
            const Text("توقيع الاستلام:", style: TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 5),
            Container(
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(15)),
              child: Image.memory(base64Decode(order['customerSignature'].split(',').last), fit: BoxFit.contain),
            ),
            const SizedBox(height: 10),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("${order['totalPrice'] ?? order['price'] ?? 0} ج.س", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.blue)),
              Row(
                children: [
                  if (canBeCancelled) 
                    TextButton(
                      onPressed: () => _cancelOrder(order['id'], order['source']),
                      child: const Text("إلغاء الطلب ❌", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(width: 5),
                  ElevatedButton.icon(
                    onPressed: () => _launchWhatsApp(),
                    icon: const Icon(Icons.chat, size: 14, color: Colors.white),
                    label: const Text("الدعم", style: TextStyle(color: Colors.white, fontSize: 10)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(width: 5),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _badge(String text, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(15)),
      child: Text(text, style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  void _launchWhatsApp() async {
    if (_supportWhatsApp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("رقم الدعم غير متوفر حالياً")));
      return;
    }
    
    final url = Uri.parse("https://wa.me/$_supportWhatsApp");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("لا يمكن فتح واتساب")));
    }
  }
}
