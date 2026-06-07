import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class CompletedOrders extends StatefulWidget {
  const CompletedOrders({super.key});

  @override
  State<CompletedOrders> createState() => _CompletedOrdersState();
}

class _CompletedOrdersState extends State<CompletedOrders> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _fetchCompletedOrders();
  }

  void _fetchCompletedOrders() {
    _db.collection('laundry_orders')
        .where('status', isEqualTo: 'completed') // جلب المكتملة فقط
        .orderBy('actualDeliveredAt', descending: true)
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() {
          _orders = snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("الطلبات المكتملة ✅", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _orders.isEmpty
                ? const Center(child: Text("لا توجد طلبات مكتملة حالياً"))
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _orders.length,
                    itemBuilder: (context, index) => _buildOrderCard(_orders[index]),
                  ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> o) {
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
              Text("تم التسليم: ${_formatTimestamp(o['actualDeliveredAt'])}", 
                  style: const TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold)),
              Text("#${o['orderNumber']}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 10),
          Text(o['userName'] ?? "عميل", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const Divider(),
          _detailRow("الكمية:", "${o['pieces']} قطعة"),
          _detailRow("المبلغ:", "${o['totalPrice']} ج.س"),
          _detailRow("الموصل:", o['deliveredByDriver'] ?? "غير محدد"),
          if (o['customerSignature'] != null) ...[
            const SizedBox(height: 10),
            const Text("توقيع العميل:", style: TextStyle(fontSize: 9, color: Colors.grey)),
            Container(
              height: 50,
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10)),
              child: Image.memory(base64Decode(o['customerSignature'].split(',').last), fit: BoxFit.contain),
            ),
          ]
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic t) {
    if (t == null) return "---";
    if (t is Timestamp) return DateFormat('dd/MM/yyyy').format(t.toDate());
    return t.toString();
  }
}
