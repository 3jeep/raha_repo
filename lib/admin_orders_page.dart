import 'dart:async';
import 'dart:math' show cos, sqrt, asin;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class MonthlyContractsPage extends StatefulWidget {
  const MonthlyContractsPage({super.key});

  @override
  State<MonthlyContractsPage> createState() => _MonthlyContractsPageState();
}

class _MonthlyContractsPageState extends State<MonthlyContractsPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  List<Map<String, dynamic>> _contracts = [];
  List<Map<String, dynamic>> _maids = [];
  List<Map<String, dynamic>> _vehicles = [];
  Map<String, List<Map<String, dynamic>>> _visitsData = {};
  bool _isLoading = true;
  DateTime _now = DateTime.now();
  Timer? _timer;

  String _filterDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final List<String> _arabicDays = ["الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"];

  @override
  void initState() {
    super.initState();
    _startTimer();
    _loadInitialData();
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

  void _loadInitialData() {
    _db.collection('maids').snapshots().listen((snap) {
      if (mounted) setState(() => _maids = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
    });
    _db.collection('vehicles').snapshots().listen((snap) {
      if (mounted) setState(() => _vehicles = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
    });
    _fetchContracts();
  }

  void _fetchContracts() {
    _db.collection('contracts').orderBy('createdAt', descending: true).snapshots().listen((snap) async {
      List<Map<String, dynamic>> raw = [];
      DateTime todayStart = DateTime(_now.year, _now.month, _now.day);
      DateTime todayEnd = todayStart.add(const Duration(hours: 23, minutes: 59, seconds: 59));

      for (var doc in snap.docs) {
        var data = doc.data();
        var vSnap = await _db.collection('contracts').doc(doc.id).collection('visits')
            .where('visitDate', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
            .where('visitDate', isLessThanOrEqualTo: Timestamp.fromDate(todayEnd))
            .limit(1).get();

        _loadVisits(doc.id);
        raw.add({'id': doc.id, ...data, 'hasVisitToday': vSnap.docs.isNotEmpty});
      }
      _applyFiltering(raw);
    });
  }

  void _loadVisits(String contractId) async {
    var snap = await _db.collection('contracts').doc(contractId).collection('visits').orderBy('visitDate', descending: true).get();
    if (mounted) setState(() => _visitsData[contractId] = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  void _applyFiltering(List<Map<String, dynamic>> all) {
    if (!mounted) return;
    setState(() {
      String selectedDayName = _arabicDays[DateFormat('yyyy-MM-dd').parse(_filterDate).weekday % 7];
      _contracts = all.where((order) {
        if (order['contractStartDate'] != null) {
          DateTime start = (order['contractStartDate'] as Timestamp).toDate();
          if (DateTime.now().difference(start).inDays > 30) return false;
        }
        List days = order['selectedDays'] ?? [];
        return days.any((d) => d.toString().replaceAll('أ', 'ا') == selectedDayName.replaceAll('أ', 'ا')) && order['status'] != "contract_finished";
      }).toList();
      _isLoading = false;
    });
  }

  String _getTimer(Map order) {
    if (order['actualStartedAt'] == null) return "00:00:00";
    DateTime start = (order['actualStartedAt'] as Timestamp).toDate();
    int durationHours = int.tryParse(order['totalHours']?.toString() ?? "5") ?? 5;
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
        child: Column(children: [
          _buildHeader(),
          _buildDateFilter(),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator()) 
              : _contracts.isEmpty 
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _contracts.length,
                      itemBuilder: (context, index) => _buildContractCard(_contracts[index]),
                    ),
          )
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 60, 25, 30),
      decoration: const BoxDecoration(color: Color(0xFF1E293B), borderRadius: BorderRadius.vertical(bottom: Radius.circular(50))),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // تعديل: استبدال FontWeight.black بـ FontWeight.w900
        Text("إدارة العقود الشهرية 🗓️", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        Text("متابعة الزيارات المتعددة وجدولة الفريق", style: TextStyle(color: Colors.white70, fontSize: 10)),
      ]),
    );
  }

  Widget _buildDateFilter() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: GestureDetector(
        onTap: () async {
          DateTime? picked = await showDatePicker(context: context, initialDate: DateTime.parse(_filterDate), firstDate: DateTime(2024), lastDate: DateTime(2030));
          if (picked != null) setState(() { _filterDate = DateFormat('yyyy-MM-dd').format(picked); _fetchContracts(); });
        },
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blue.withOpacity(0.1))),
          child: Row(children: [
            const Icon(Icons.calendar_month, color: Colors.blue, size: 20),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("تاريخ استعراض الزيارات", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
              // تعديل: استبدال FontWeight.black بـ FontWeight.w900
              Text(_filterDate, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _buildContractCard(Map<String, dynamic> b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: Colors.blue[50]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(20)), child: const Text("عقد نشط ✅", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))),
          IconButton(onPressed: () => _db.collection('contracts').doc(b['id']).delete(), icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20)),
        ]),
        const SizedBox(height: 10),
        // تعديل: استبدال FontWeight.black بـ FontWeight.w900
        Text(b['fullName'] ?? b['userName'] ?? "عميل", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        Text("📞 ${b['phone']}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),

        if (_visitsData[b['id']] != null && _visitsData[b['id']]!.isNotEmpty) ...[
          const SizedBox(height: 15),
          const Text("📊 سجل الزيارات المكتملة:", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 8),
          SizedBox(height: 65, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _visitsData[b['id']]!.length, itemBuilder: (context, i) {
            var v = _visitsData[b['id']]![i];
            return Container(width: 90, margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue[50]?.withOpacity(0.5), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.blue[100]!)), child: Column(children: [
              Text("زيارة #${_visitsData[b['id']]!.length - i}", style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
              // تعديل: استبدال FontWeight.black بـ FontWeight.w900
              Text(v['rating'] ?? "-", style: const TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.w900)),
            ]));
          }))
        ],

        const Divider(height: 40),
        const Text("تعيين الفريق لهذه الزيارة:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _assignmentDropdown("العاملة", b['assignedMaid'], _maids, (v) => _db.collection('contracts').doc(b['id']).update({'assignedMaid': v}))),
          const SizedBox(width: 10),
          Expanded(child: _assignmentDropdown("السائق", b['assignedVehicle'], _vehicles, (v) => _db.collection('contracts').doc(b['id']).update({'assignedVehicle': v}))),
        ]),
        const SizedBox(height: 25),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: b['hasVisitToday'] == true ? null : () => _handleStart(b),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)), disabledBackgroundColor: Colors.grey[200]),
          child: b['status'] == "in-progress" 
            // تعديل: استبدال FontWeight.black بـ FontWeight.w900
            ? Text(_getTimer(b), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, fontFamily: 'monospace'))
            : Text(b['hasVisitToday'] == true ? "تم إكمال زيارة اليوم ✅" : "بدء الزيارة الحالية 🚀", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ))
      ]),
    );
  }

  Widget _assignmentDropdown(String label, String? current, List<Map<String, dynamic>> items, Function(String) onSave) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[200]!)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(
      isExpanded: true, hint: Text(label, style: const TextStyle(fontSize: 11)),
      value: items.any((e) => e['name'] == current) ? current : null,
      items: items.map((e) => DropdownMenuItem(value: e['name'].toString(), child: Text(e['name'] ?? "", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)))).toList(),
      onChanged: (v) => onSave(v!),
    )));
  }

  void _handleStart(Map b) async {
    if (b['assignedMaid'] == null || b['assignedVehicle'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text("⚠️ يرجى تعيين الفريق أولاً")));
      return;
    }
    Map<String, dynamic> updates = {'status': 'in-progress', 'actualStartedAt': FieldValue.serverTimestamp()};
    if (b['contractStartDate'] == null) updates['contractStartDate'] = FieldValue.serverTimestamp();
    await _db.collection('contracts').doc(b['id']).update(updates);
    await _db.collection('contracts').doc(b['id']).collection('visits').add({'type': 'start_record', 'visitDate': FieldValue.serverTimestamp(), 'status': 'started', 'maid': b['assignedMaid'], 'vehicle': b['assignedVehicle']});
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.event_busy, size: 80, color: Colors.grey[300]), const SizedBox(height: 20), const Text("لا توجد عقود مجدولة لهذا اليوم", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))]));
  }
}
