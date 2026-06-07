import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SingleVisitsCompletedPage extends StatefulWidget {
  final String adminType; 
  const SingleVisitsCompletedPage({super.key, this.adminType = 'cleaning'});

  @override
  State<SingleVisitsCompletedPage> createState() => _SingleVisitsCompletedPageState();
}

class _SingleVisitsCompletedPageState extends State<SingleVisitsCompletedPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  DateTime _selectedDate = DateTime.now();
  bool _isFilteredByDate = false;
  String _searchQuery = "";
  bool _loading = true;
  List<Map<String, dynamic>> _completedBookings = [];

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("تعذر فتح الرابط")),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchCompletedData();
  }

  void _fetchCompletedData() {
    if (!mounted) return;
    setState(() => _loading = true);
    
    _db.collection('bookings')
        .where('status', isEqualTo: 'completed')
        .where('serviceType', isEqualTo: 'single_visit')
        .orderBy('actualFinishedAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          if (mounted) {
            setState(() {
              _completedBookings = snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
              _loading = false;
            });
          }
        });
  }

  List<Map<String, dynamic>> _getFilteredBookings() {
    return _completedBookings.where((b) {
      bool dateMatch = true;
      if (_isFilteredByDate) {
        dateMatch = b['startDate'] == _selectedDate.toString().split(' ')[0];
      }

      bool searchMatch = true;
      if (_searchQuery.isNotEmpty) {
        searchMatch = (b['fullName'] ?? "").toString().contains(_searchQuery) ||
                      (b['phone'] ?? "").toString().contains(_searchQuery);
      }

      return dateMatch && searchMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _getFilteredBookings();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text("سجل الزيارات المكتملة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            _buildSearchAndFilter(),
            Expanded(
              child: _loading 
                ? const Center(child: CircularProgressIndicator())
                : filteredList.isEmpty 
                  ? const Center(child: Text("لا توجد زيارات مكتملة حالياً"))
                  : ListView.builder(
                      padding: const EdgeInsets.all(15),
                      itemCount: filteredList.length,
                      itemBuilder: (context, index) => _buildCompletedCard(filteredList[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: "بحث باسم العميل أو الهاتف...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() { _selectedDate = picked; _isFilteredByDate = true; });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: _isFilteredByDate ? Colors.blue.withOpacity(0.1) : Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text(_isFilteredByDate ? _selectedDate.toString().split(' ')[0] : "تصفية بالتاريخ", style: TextStyle(color: _isFilteredByDate ? Colors.blue : Colors.black, fontWeight: FontWeight.bold))),
                  ),
                ),
              ),
              if (_isFilteredByDate) IconButton(onPressed: () => setState(() => _isFilteredByDate = false), icon: const Icon(Icons.close, color: Colors.red)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedCard(Map<String, dynamic> b) {
    // تنسيق وعرض أوقات العمل الفعلي (البداية والنهاية)
    String startTime = "غير محدد";
    String endTime = "غير محدد";
    if (b['actualStartedAt'] != null && b['actualStartedAt'] is Timestamp) {
      DateTime start = (b['actualStartedAt'] as Timestamp).toDate();
      startTime = "${start.hour}:${start.minute.toString().padLeft(2, '0')}";
    }
    if (b['actualFinishedAt'] != null && b['actualFinishedAt'] is Timestamp) {
      DateTime finish = (b['actualFinishedAt'] as Timestamp).toDate();
      endTime = "${finish.hour}:${finish.minute.toString().padLeft(2, '0')}";
    }

    // جلب قائمة العاملات المستندة للطلب
    List assignedMaids = b['assignedMaidsList'] ?? [];
    String maidsNames = assignedMaids.isNotEmpty ? assignedMaids.join('، ') : (b['assignedMaid'] ?? "لم يتم تحديد عاملات");

    // السائق والمشرف
    String driverName = b['assignedVehicle'] ?? "غير محدد";
    String completedByAdmin = b['completedBy'] ?? "نظام التشغيل تلقائي";

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(b['fullName'] ?? "بدون اسم", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              _ratingBadge(b['rating'] ?? "غير مقيم"),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.location_on, size: 14, color: Colors.grey),
              const SizedBox(width: 5),
              Text("${b['region'] ?? 'غير محدد'} - ", style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
              Expanded(child: Text(b['locationText'] ?? "لا يوجد عنوان", style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const Divider(height: 25),
          
          // --- تفاصيل طاقم العمل والمسؤولين المنفذين ---
          _buildDetailRow(Icons.engineering_rounded, "العاملات المنفذات:", maidsNames, Colors.purple),
          const SizedBox(height: 6),
          _buildDetailRow(Icons.local_shipping_rounded, "السائق / المركبة:", driverName, Colors.amber[800]!),
          const SizedBox(height: 6),
          _buildDetailRow(Icons.admin_panel_settings_rounded, "المشرف المسؤول:", completedByAdmin, Colors.blueGrey),
          
          const Divider(height: 25),
          
          // رقاقات المعلومات السريعة والأوقات
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _infoChip(Icons.calendar_today, b['startDate'] ?? ""),
              _infoChip(Icons.play_circle_filled, "البدء: $startTime", iconColor: Colors.green),
              _infoChip(Icons.stop_circle, "النهاية: $endTime", iconColor: Colors.red),
              _infoChip(Icons.payments, "${b['price'] ?? 0} ج.س"),
            ],
          ),
          
          // --- قسم توقيع العميل (إذا كان التوقيع مخزناً كرابط أو نص) ---
          if (b['signatureUrl'] != null || b['signatureData'] != null) ...[
            const Divider(height: 25),
            const Text("📝 توقيع إتمام العميل:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 8),
            Container(
              height: 80,
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
              child: b['signatureUrl'] != null 
                ? Image.network(b['signatureUrl'], errorBuilder: (c, e, s) => const Center(child: Icon(Icons.gesture, color: Colors.grey)))
                : const Center(child: Text("تم التوقيع إلكترونياً على الجهاز ✒️", style: TextStyle(fontSize: 11, color: Colors.grey))),
            ),
          ],
          
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (b['phone'] != null) _actionCircle(Icons.phone, Colors.green, () => _launchURL("tel:${b['phone']}")),
              const SizedBox(width: 10),
              if (b['locationCoords'] != null)
                _actionCircle(Icons.map, Colors.blue, () {
                  double lat = b['locationCoords']['lat'];
                  double lng = b['locationCoords']['lng'];
                  _launchURL("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
                }),
              const SizedBox(width: 10),
              _actionCircle(Icons.delete_outline, Colors.red, () => _confirmDelete(b['id'])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String title, String value, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
        const SizedBox(width: 6),
        Expanded(child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[800]))),
      ],
    );
  }

  Widget _ratingBadge(String rating) {
    Color color = rating == 'ممتاز' ? Colors.green : (rating == 'جيد' ? Colors.blue : Colors.orange);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Text(rating, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _infoChip(IconData icon, String label, {Color iconColor = Colors.blue}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _actionCircle(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("حذف السجل"),
        content: const Text("هل أنت متأكد من حذف هذا الطلب المكتمل نهائياً؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("تراجع")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.collection('bookings').doc(id).delete();
              if (mounted) Navigator.pop(context);
            },
            child: const Text("حذف", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
