import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_signaturepad/signaturepad.dart'; 
import 'package:url_launcher/url_launcher.dart'; 
import 'fcm_sender.dart'; 
import 'monthly_contracts_completed.dart'; // استيراد صفحة المكتملة

class MonthlyContractsPage extends StatefulWidget {
  final String adminType; 
  const MonthlyContractsPage({super.key, this.adminType = 'super'});

  @override
  State<MonthlyContractsPage> createState() => _MonthlyContractsPageState();
}

class _MonthlyContractsPageState extends State<MonthlyContractsPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GlobalKey<SfSignaturePadState> _signaturePadKey = GlobalKey();

  List<Map<String, dynamic>> _contracts = [];
  List<Map<String, dynamic>> _allContractsRaw = []; 
  List<Map<String, dynamic>> _maids = [];
  List<Map<String, dynamic>> _vehicles = [];
  Map<String, List<Map<String, dynamic>>> _visitsData = {};
  bool _isLoading = true;
  DateTime _now = DateTime.now();
  Timer? _timer;

  String _searchQuery = ""; 
  String? _filterDate; 
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
        if (widget.adminType != 'super' && data['isPublished'] != true) continue;

        var vSnap = await _db.collection('contracts').doc(doc.id).collection('visits')
            .where('visitDate', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
            .where('visitDate', isLessThanOrEqualTo: Timestamp.fromDate(todayEnd))
            .limit(1).get();

        _loadVisits(doc.id);
        
        String? smartMaid = data['assignedMaid'];
        if (smartMaid == null) {
          var lastVisits = await _db.collection('contracts').doc(doc.id).collection('visits').orderBy('visitDate', descending: true).limit(1).get();
          if (lastVisits.docs.isNotEmpty) {
            smartMaid = lastVisits.docs.first.data()['maid'];
          }
        }

        raw.add({
          'id': doc.id, 
          ...data, 
          'hasVisitToday': vSnap.docs.isNotEmpty,
          'assignedMaid': smartMaid,
        });
      }
      _allContractsRaw = raw; 
      _applyFiltering(_allContractsRaw);
    });
  }

  void _loadVisits(String contractId) async {
    var snap = await _db.collection('contracts').doc(contractId).collection('visits').orderBy('visitDate', descending: true).get();
    if (mounted) setState(() => _visitsData[contractId] = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  void _applyFiltering(List<Map<String, dynamic>> all) {
    if (!mounted) return;
    setState(() {
      _contracts = all.where((order) {
        bool matchesDay = true;
        if (_filterDate != null) {
          String selectedDayName = _arabicDays[DateFormat('yyyy-MM-dd').parse(_filterDate!).weekday % 7];
          List days = order['selectedDays'] ?? [];
          matchesDay = days.any((d) => d.toString().replaceAll('أ', 'ا') == selectedDayName.replaceAll('أ', 'ا')) && order['status'] != "contract_finished";
        }
        bool matchesSearch = _searchQuery.isEmpty || 
            (order['fullName'] ?? "").toString().contains(_searchQuery) || 
            (order['id'] ?? "").toString().contains(_searchQuery);
        return matchesDay && matchesSearch;
      }).toList();
      _isLoading = false;
    });
  }

  String _getTimer(Map order) {
    if (order['actualStartedAt'] == null || order['isPaused'] == true) return "00:00:00";
    DateTime start = (order['actualStartedAt'] as Timestamp).toDate();
    int durationHours = int.tryParse(order['totalHours']?.toString() ?? "5") ?? 5;
    DateTime end = start.add(Duration(hours: durationHours));
    Duration diff = end.difference(_now);
    if (diff.isNegative) return "00:00:00";
    return "${diff.inHours.toString().padLeft(2, '0')}:${(diff.inMinutes % 60).toString().padLeft(2, '0')}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
  }

  Future<bool> _showConfirmDialog(String title, String content, Color confirmColor) async {
    return await showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Text(content),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("إلغاء", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: confirmColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => Navigator.pop(context, true), 
              child: const Text("تأكيد", style: TextStyle(color: Colors.white))
            ),
          ],
        ),
      ),
    ) ?? false;
  }

  void _finishVisitWithRating(Map b) {
    String rating = "ممتاز";
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        return Container(
          padding: EdgeInsets.fromLTRB(25, 25, 25, MediaQuery.of(context).viewInsets.bottom + 25),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text("إنهاء الزيارة والتقييم ✍️", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _buildRatingOption("ممتاز", "🤩", rating, (val) => setModalState(() => rating = val)),
              _buildRatingOption("جيد", "🙂", rating, (val) => setModalState(() => rating = val)),
              _buildRatingOption("سيئ", "😞", rating, (val) => setModalState(() => rating = val)),
            ]),
            const SizedBox(height: 25),
            const Align(alignment: Alignment.centerRight, child: Text("توقيع العميل:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            const SizedBox(height: 10),
            Container(
              height: 200, 
              decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!, width: 2), borderRadius: BorderRadius.circular(20), color: Colors.grey[50]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SfSignaturePad(key: _signaturePadKey, backgroundColor: Colors.transparent, strokeColor: Colors.black, minimumStrokeWidth: 4.0),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: TextButton(onPressed: () => _signaturePadKey.currentState?.clear(), child: const Text("مسح التوقيع", style: TextStyle(color: Colors.red)))),
              Expanded(flex: 2, child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                onPressed: () async {
                  bool confirm = await _showConfirmDialog("إنهاء الزيارة", "هل أنت متأكد من إنهاء الزيارة الحالية؟", Colors.blue);
                  if (!confirm) return;
                  await _db.collection('contracts').doc(b['id']).update({'status': 'active', 'isPaused': false, 'actualStartedAt': null});
                  var lastVisit = await _db.collection('contracts').doc(b['id']).collection('visits').orderBy('visitDate', descending: true).limit(1).get();
                  if (lastVisit.docs.isNotEmpty) {
                    await lastVisit.docs.first.reference.update({'rating': rating, 'status': 'completed', 'endedAt': FieldValue.serverTimestamp()});
                  }
                  if (b['fcmToken'] != null) FcmSender.sendNotification(b['fcmToken'], "زيارة سعيدة ✨", "شكراً لتقييمك.");
                  Navigator.pop(context);
                },
                child: const Text("حفظ وإكمال ✅", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )),
            ]),
          ]),
        );
      }),
    );
  }

  Widget _buildRatingOption(String label, String emoji, String current, Function(String) onSelect) {
    bool isSelected = current == label;
    return GestureDetector(
      onTap: () => onSelect(label),
      child: Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: isSelected ? const Color(0xFF1E293B) : Colors.grey[100], shape: BoxShape.circle, border: Border.all(color: isSelected ? Colors.blue : Colors.transparent, width: 2)),
          child: Text(emoji, style: const TextStyle(fontSize: 25)),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Column(children: [
          _buildHeader(),
          _buildSearchAndFilter(), 
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator()) 
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("إدارة العقود الشهرية 🗓️", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
            Text("متابعة الزيارات وجدولة الفريق الذكية", style: TextStyle(color: Colors.white70, fontSize: 10)),
          ]),
          // الزر المضاف للانتقال لصفحة الزيارات المكتملة
          GestureDetector(
            onTap: () {
              Navigator.push(
                context, 
                MaterialPageRoute(builder: (context) => const MonthlyContractsCompletedPage())
              );
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white24)
              ),
              child: const Column(
                children: [
                  Icon(Icons.history, color: Colors.white, size: 24),
                  Text("السجل", style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blue.withOpacity(0.1))),
          child: TextField(
            onChanged: (v) {
              _searchQuery = v;
              _applyFiltering(_allContractsRaw);
            },
            decoration: const InputDecoration(
              icon: Icon(Icons.search, color: Colors.blue),
              hintText: "بحث بالاسم أو رقم العقد...",
              border: InputBorder.none,
              hintStyle: TextStyle(fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () async {
            DateTime? picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
            if (picked != null) {
              setState(() => _filterDate = DateFormat('yyyy-MM-dd').format(picked));
              _applyFiltering(_allContractsRaw);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blue.withOpacity(0.1))),
            child: Row(children: [
              const Icon(Icons.calendar_today, color: Colors.blue, size: 20),
              const SizedBox(width: 12),
              Text(_filterDate ?? "عرض كل العقود (اضغط للفلترة بالتاريخ)", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
              const Spacer(),
              if (_filterDate != null)
                IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.red), onPressed: () { setState(() => _filterDate = null); _applyFiltering(_allContractsRaw); })
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildContractCard(Map<String, dynamic> b) {
    String createdAtStr = b['createdAt'] != null ? DateFormat('yyyy-MM-dd').format((b['createdAt'] as Timestamp).toDate()) : "غير متوفر";
    String startDateStr = b['contractStartDate'] != null ? DateFormat('yyyy-MM-dd').format((b['contractStartDate'] as Timestamp).toDate()) : "لم يبدأ بعد";
    String selectedDaysStr = (b['selectedDays'] as List?)?.join(" - ") ?? "غير محدد";
    String region = b['region'] ?? "غير محددة";
    bool isPublished = b['isPublished'] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(b['fullName'] ?? "عميل بدون اسم", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
        const SizedBox(height: 8),

        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.map, size: 14, color: Colors.blue),
              const SizedBox(width: 5),
              Text("المنطقة: $region", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue)),
            ]),
          ),
          const Spacer(),
          IconButton(icon: const Icon(Icons.location_on, color: Colors.redAccent, size: 22), onPressed: () async {
              var coords = b['locationCoords'] as Map?;
              if (coords != null && coords['lat'] != null) {
                final String googleMapsUrl = "https://www.google.com/maps/search/?api=1&query=${coords['lat']},${coords['lng']}";
                if (await canLaunchUrl(Uri.parse(googleMapsUrl))) await launchUrl(Uri.parse(googleMapsUrl), mode: LaunchMode.externalApplication);
              }
          }),
          IconButton(icon: const Icon(Icons.call, color: Colors.green, size: 20), onPressed: () => launchUrl(Uri.parse("tel:${b['phone']}"))),
          IconButton(icon: const Icon(Icons.chat, color: Colors.teal, size: 20), onPressed: () => launchUrl(Uri.parse("https://wa.me/${b['phone']}"))),
          if (b['status'] == "in-progress")
             IconButton(icon: Icon(b['isPaused'] == true ? Icons.play_circle : Icons.pause_circle, color: Colors.orange), onPressed: () => _db.collection('contracts').doc(b['id']).update({'isPaused': !(b['isPaused'] ?? false)})),
          if (widget.adminType == 'super')
             IconButton(icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 20), onPressed: () async {
                 bool confirm = await _showConfirmDialog("حذف العقد", "هل أنت متأكد؟", Colors.red);
                 if (confirm) _db.collection('contracts').doc(b['id']).delete();
             }),
        ]),
        
        const SizedBox(height: 10),
        Text("رقم الوثيقة: ${b['id']}", style: const TextStyle(color: Colors.blueGrey, fontSize: 10, fontWeight: FontWeight.bold)),
        Text("تاريخ الطلب: $createdAtStr", style: const TextStyle(color: Colors.grey, fontSize: 10)),
        Text("تاريخ البدء: $startDateStr", style: const TextStyle(color: Colors.grey, fontSize: 10)),
        Text("الأيام: $selectedDaysStr", style: const TextStyle(color: Color(0xFF1E293B), fontSize: 10, fontWeight: FontWeight.bold)),
        
        const SizedBox(height: 15),
        if (_visitsData[b['id']] != null) _buildVisitsLog(b['id'], _visitsData[b['id']]!),
        const Divider(height: 30),
        const Text("تعيين الفريق:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _assignmentDropdown("العاملة", b['assignedMaid'], _maids, "name", (v) => _db.collection('contracts').doc(b['id']).update({'assignedMaid': v}))),
          const SizedBox(width: 10),
          Expanded(child: _assignmentDropdown("السائق", b['driverName'], _vehicles, "driverName", (v) => _db.collection('contracts').doc(b['id']).update({'driverName': v}))),
        ]),
        const SizedBox(height: 15),
        
        if (widget.adminType == 'super')
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                bool newStatus = !isPublished;
                bool confirm = await _showConfirmDialog("تحديث الحالة", "تأكيد الإجراء؟", Colors.green);
                if (confirm) _db.collection('contracts').doc(b['id']).update({'isPublished': newStatus});
              },
              icon: Icon(isPublished ? Icons.undo : Icons.check_circle_outline, size: 18),
              label: Text(isPublished ? "تراجع عن النشر" : "تأكيد الدفع ونشر للمشرف", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(foregroundColor: isPublished ? Colors.orange : Colors.green, side: BorderSide(color: isPublished ? Colors.orange : Colors.green), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            ),
          ),

        const SizedBox(height: 25),
        _buildActionButton(b),
      ]),
    );
  }

  Widget _buildVisitsLog(String contractId, List visits) {
    return SizedBox(
      height: 65,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: visits.length,
        itemBuilder: (context, i) => Container(
          width: 90, margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(15)),
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("زيارة #${visits.length - i}", style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
              Text(visits[i]['rating'] ?? "مكتمل", style: const TextStyle(fontSize: 8, color: Colors.blue)),
            ]),
            Positioned(left: -10, top: -10, child: IconButton(icon: const Icon(Icons.close, size: 12, color: Colors.red), onPressed: () => _db.collection('contracts').doc(contractId).collection('visits').doc(visits[i]['id']).delete()))
          ]),
        ),
      ),
    );
  }

  Widget _buildActionButton(Map b) {
    bool inProgress = b['status'] == "in-progress";
    String todayName = _arabicDays[DateTime.now().weekday % 7];
    List selectedDays = b['selectedDays'] ?? [];
    bool isTodayAllowed = selectedDays.any((d) => d.toString().replaceAll('أ', 'ا') == todayName.replaceAll('أ', 'ا'));

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (b['hasVisitToday'] == true && !inProgress) || (!inProgress && !isTodayAllowed) ? null : () {
          if (inProgress) _finishVisitWithRating(b); else _handleStart(b);
        },
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)), disabledBackgroundColor: Colors.grey[300]),
        child: inProgress && b['isPaused'] != true
          ? Text(_getTimer(b), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, fontFamily: 'monospace'))
          : Text(b['hasVisitToday'] == true && !inProgress ? "تم إكمال زيارة اليوم ✅" : (!inProgress && !isTodayAllowed ? "اليوم ليس ضمن الحجز ⚠️" : (inProgress ? "إنهاء الزيارة 🏁" : "بدء الزيارة 🚀")), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _assignmentDropdown(String label, String? current, List<Map<String, dynamic>> items, String fieldName, Function(String) onSave) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[200]!)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          hint: Text(label, style: const TextStyle(fontSize: 10)),
          value: items.any((e) => e[fieldName] == current) ? current : null,
          items: items.map((e) => DropdownMenuItem(value: e[fieldName].toString(), child: Text(e[fieldName].toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)))).toList(),
          onChanged: (v) => onSave(v!),
        ),
      ),
    );
  }

  void _handleStart(Map b) async {
    if (b['assignedMaid'] == null || b['driverName'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ عين الفريق أولاً")));
      return;
    }
    bool confirm = await _showConfirmDialog("بدء الزيارة", "تأكيد البدء؟", Colors.green);
    if (!confirm) return;

    Map<String, dynamic> updates = {'status': 'in-progress', 'actualStartedAt': FieldValue.serverTimestamp(), 'isPaused': false};
    if (b['contractStartDate'] == null) updates['contractStartDate'] = FieldValue.serverTimestamp();
    await _db.collection('contracts').doc(b['id']).update(updates);
    await _db.collection('contracts').doc(b['id']).collection('visits').add({'visitDate': FieldValue.serverTimestamp(), 'maid': b['assignedMaid'], 'vehicle': b['driverName']});
  }
}
