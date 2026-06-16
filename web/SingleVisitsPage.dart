import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:syncfusion_flutter_signaturepad/signaturepad.dart';

class SingleVisitsPage extends StatefulWidget {
  final String adminType;
  const SingleVisitsPage({super.key, this.adminType = 'super'});

  @override
  State<SingleVisitsPage> createState() => _SingleVisitsPageState();
}

class _SingleVisitsPageState extends State<SingleVisitsPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GlobalKey<SfSignaturePadState> _signaturePadKey = GlobalKey();

  DateTime _filterDate = DateTime.now();
  String _searchQuery = "";
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  String _getTimer(Map v) {
    if (v['actualStartedAt'] == null || v['status'] == 'completed')
      return "00:00:00";

    DateTime start = (v['actualStartedAt'] as Timestamp).toDate();
    int durationHours = int.tryParse(v['totalHours']?.toString() ?? "5") ?? 5;

    DateTime end = start.add(Duration(hours: durationHours));
    Duration diff = end.difference(_now);

    if (diff.isNegative) return "00:00:00";

    return "${diff.inHours.toString().padLeft(2, '0')}:${(diff.inMinutes % 60).toString().padLeft(2, '0')}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Column(
          children: [
            _buildHeader(),
            _buildTopFilters(),
            Expanded(child: _buildOrdersList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 60, 25, 30),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(50)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("الزيارات المنفردة 🚀",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
              Text("إدارة الطلبات العابرة",
                  style: TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
          if (widget.adminType == 'super')
            const Icon(Icons.admin_panel_settings,
                color: Colors.blue, size: 30),
        ],
      ),
    );
  }

  Widget _buildTopFilters() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _filterDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime(2027),
                    );
                    if (picked != null) {
                      setState(() => _filterDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      DateFormat('yyyy-MM-dd').format(_filterDate),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: "بحث بالاسم أو الهاتف...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ هنا التعديل الحقيقي فقط (إزالة التاريخ)
  Widget _buildOrdersList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('Bookings').snapshots(), // ❌ بدون فلتر تاريخ
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var docs = snapshot.data!.docs.where((doc) {
          var data = doc.data() as Map<String, dynamic>;
          var name = (data['fullName'] ?? "").toString().toLowerCase();
          var phone = (data['phone'] ?? "").toString();

          return name.contains(_searchQuery.toLowerCase()) ||
              phone.contains(_searchQuery);
        }).toList();

        if (docs.isEmpty) {
          return const Center(child: Text("لا توجد طلبات 🕊️"));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: docs.length,
          itemBuilder: (context, index) => _buildOrderCard(docs[index]),
        );
      },
    );
  }

  Widget _buildOrderCard(DocumentSnapshot doc) {
    var v = doc.data() as Map<String, dynamic>;

    bool isProgress = v['status'] == 'in-progress';
    bool isCompleted = v['status'] == 'completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v['fullName'] ?? "بدون اسم",
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Text(v['phone'] ?? ""),
          const SizedBox(height: 10),
          Text(v['locationText'] ?? ""),
          const SizedBox(height: 20),
          if (isProgress)
            Text(_getTimer(v),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
          else if (!isCompleted)
            ElevatedButton(
              onPressed: () {
                _db.collection('Bookings').doc(doc.id).update({
                  'status': 'in-progress',
                  'actualStartedAt': FieldValue.serverTimestamp(),
                });
              },
              child: const Text("بدء"),
            )
          else
            const Text("مكتمل"),
        ],
      ),
    );
  }
}
