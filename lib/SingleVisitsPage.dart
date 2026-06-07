import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:syncfusion_flutter_signaturepad/signaturepad.dart';
import 'package:firebase_auth/firebase_auth.dart';
// استيراد ملفات الإشعارات والخدمات
import 'fcm_sender.dart'; 
import 'notification_service.dart';
import 'Single_Visits_completed.dart';

class SingleVisitsPage extends StatefulWidget {
  final String adminType; 
  const SingleVisitsPage({super.key, this.adminType = 'super'});

  @override
  State<SingleVisitsPage> createState() => _SingleVisitsPageState();
}

class _SingleVisitsPageState extends State<SingleVisitsPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GlobalKey<SfSignaturePadState> _signaturePadKey = GlobalKey();
  
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _maids = [];
  List<Map<String, dynamic>> _vehicles = [];
  bool _loading = true;
  bool _isFiltered = false; 
  Timer? _timer;
  
  String _selectedRating = "ممتاز"; 

  @override
  void initState() {
    super.initState();
    // تحديث الواجهة كل ثانية لتشغيل العداد الزمني
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
    _fetchData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _launchURL(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تعذر فتح الرابط")));
      }
    }
  }

  void _fetchData() {
    if (mounted) setState(() => _loading = true);

    _db.collection('maids').snapshots().listen((snap) {
      if (mounted) setState(() => _maids = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
    });

    _db.collection('vehicles').snapshots().listen((snap) {
      if (mounted) setState(() => _vehicles = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
    });

    _db.collection('bookings').snapshots().listen((snap) {
      if (mounted) {
        String selectedDateStr = _selectedDate.toIso8601String().split('T')[0];
        setState(() {
          _bookings = snap.docs.map((doc) => {'id': doc.id, ...doc.data()}).where((order) {
            var type = order['serviceType']?.toString().toLowerCase();
            bool isSingle = (type == 'single_visit' || type == 'single' || type == null);
            bool isNotCompleted = order['status'] != 'completed';
            
            bool isConfirmedBySuper = order['paymentStatus'] == 'confirmed';
            bool canSeeOrder = (widget.adminType == 'super') || isConfirmedBySuper;

            if (!canSeeOrder) return false;
            if (!_isFiltered) return isSingle && isNotCompleted;

            var rawDate = order['startDate'];
            String orderDateStr = "";
            if (rawDate is Timestamp) {
              orderDateStr = rawDate.toDate().toIso8601String().split('T')[0];
            } else {
              orderDateStr = rawDate?.toString().split('T')[0] ?? "";
            }
            return isSingle && isNotCompleted && orderDateStr == selectedDateStr;
          }).toList();
          _loading = false;
        });
      }
    });
  }

  String _getTimer(Map order) {
    if (order['actualStartedAt'] == null) return "00:00:00";
    DateTime start = (order['actualStartedAt'] as Timestamp).toDate();
    int totalHours = int.tryParse(order['totalHours']?.toString() ?? '5') ?? 5;
    DateTime end = start.add(Duration(hours: totalHours));
    Duration diff = end.difference(DateTime.now());
    
    if (diff.isNegative) return "انتهى الوقت ⚠️";
    
    return "${diff.inHours.toString().padLeft(2, '0')}:${(diff.inMinutes % 60).toString().padLeft(2, '0')}:${(diff.inSeconds % 60).toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            _buildHeader(),
            _buildDateBar(),
            if (_loading) const LinearProgressIndicator(),
            Expanded(child: _buildOrdersList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 30),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.flash_on, color: Colors.amber, size: 28),
                  SizedBox(width: 10),
                  Text("الزيارات المنفردة ⚡", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SingleVisitsCompletedPage(adminType: widget.adminType)),
                  );
                },
                icon: const Icon(Icons.history_rounded, color: Colors.white, size: 28),
              ),
            ],
          ),
          if (_isFiltered)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ActionChip(
                  label: const Text("عرض كل الطلبات", style: TextStyle(color: Colors.white, fontSize: 12)),
                  backgroundColor: Colors.blueAccent.withOpacity(0.4),
                  onPressed: () => setState(() => _isFiltered = false),
                ),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildDateBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: InkWell(
        onTap: () async {
          DateTime? p = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2024), lastDate: DateTime(2100));
          if (p != null) { 
            setState(() {
              _selectedDate = p;
              _isFiltered = true;
            }); 
            _fetchData(); 
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: _isFiltered ? Colors.blue : Colors.grey[200]!)),
          child: Row(children: [
            Icon(Icons.calendar_today, size: 18, color: _isFiltered ? Colors.blue : Colors.grey),
            const SizedBox(width: 10),
            Text(_isFiltered ? "تاريخ: ${_selectedDate.toString().split(' ')[0]}" : "تصفية حسب التاريخ", 
              style: TextStyle(fontWeight: FontWeight.bold, color: _isFiltered ? Colors.blue : Colors.black)),
            const Spacer(),
            if (_isFiltered) const Icon(Icons.check_circle, color: Colors.blue, size: 20),
          ]),
        ),
      ),
    );
  }

  Widget _buildOrdersList() {
    if (_bookings.isEmpty && !_loading) {
      return const Center(child: Text("لا توجد طلبات حالية 🔍", style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _bookings.length,
      itemBuilder: (context, index) {
        final b = _bookings[index];
        bool isInProgress = b['status'] == 'in-progress';
        bool isConfirmed = b['paymentStatus'] == 'confirmed';

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(b),
              const SizedBox(height: 10),
              Text(b['fullName'] ?? "بدون اسم", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: Colors.blue),
                  const SizedBox(width: 5),
                  Text("${b['region'] ?? 'غير محدد'} - ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Expanded(child: Text(b['locationText'] ?? "لا يوجد عنوان", style: const TextStyle(fontSize: 12, color: Colors.black54), overflow: TextOverflow.ellipsis)),
                ],
              ),
              const SizedBox(height: 10),
              _buildQuickActions(b),
              const Divider(height: 30),
              if (!isInProgress) ...[
                _buildSelectors(b),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(child: _buildActionButton(b, "بدء المهمة 🚀", Colors.blue, () => _startTask(b))),
                    if (widget.adminType == 'super') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: isConfirmed 
                        ? _buildActionButton(b, "تراجع عن التأكيد ↩️", Colors.redAccent, () => _undoConfirmPayment(b))
                        : _buildActionButton(b, "تأكيد وإرسال للمشرف", Colors.orange, () => _confirmPaymentAndSend(b)),
                      ),
                    ],
                  ],
                ),
              ] else ...[
                _buildProgressView(b),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar(Map b) {
  String shiftText = b['shift'] == 'morning' ? "صباحي ☀️" : "مسائي 🌙";
  Color shiftColor = b['shift'] == 'morning' ? Colors.orange : Colors.indigo;

  // تهيئة وتنسيق تاريخ الإنشاء إذا كان موجوداً
  String createdDateStr = "غير متوفر";
  if (b['createdAt'] != null && b['createdAt'] is Timestamp) {
    DateTime createdDate = (b['createdAt'] as Timestamp).toDate();
    createdDateStr = "${createdDate.year}-${createdDate.month.toString().padLeft(2,'0')}-${createdDate.day.toString().padLeft(2,'0')}";
  }

  // تهيئة تاريخ الزيارة
  String visitDateStr = b['startDate']?.toString().split(' ')[0] ?? "غير محدد";

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: shiftColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(shiftText, style: TextStyle(fontSize: 10, color: shiftColor, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            _infoTile(Icons.people, "${b['maidsCount'] ?? '1'} عاملات"),
            const SizedBox(width: 10),
            _infoTile(Icons.access_time, "${b['totalHours'] ?? '5'}س"),
          ]),
          if (widget.adminType == 'super') 
            IconButton(onPressed: () => _deleteBooking(b), icon: const Icon(Icons.delete_sweep, color: Colors.redAccent)),
        ],
      ),
      const SizedBox(height: 8),
      // إضافة ليبل تاريخ الإنشاء وتاريخ الزيارة أسفل العناصر العلوية
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("📅 تاريخ الزيارة: $visitDateStr", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          Text("📝 طُلب في: $createdDateStr", style: TextStyle(fontSize: 10, color: Colors.grey[500])),
        ],
      ),
    ],
  );
}


  Widget _infoTile(IconData icon, String text) {
    return Row(children: [Icon(icon, size: 14, color: Colors.grey), const SizedBox(width: 4), Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))]);
  }

  Widget _buildQuickActions(Map b) {
    String phone = b['phone'] ?? "";
    return Row(
      children: [
        IconButton(onPressed: () => _launchURL("tel:$phone"), icon: const Icon(Icons.phone_in_talk, color: Colors.green)),
        IconButton(onPressed: () => _launchURL("https://wa.me/$phone"), icon: const Icon(Icons.chat_bubble_outline, color: Colors.teal)),
        if (b['locationCoords'] != null)
          IconButton(onPressed: () => _launchURL("http://maps.google.com/?q=${b['locationCoords']['lat']},${b['locationCoords']['lng']}"), icon: const Icon(Icons.map, color: Colors.blue)),
      ],
    );
  }

  Widget _buildSelectors(Map b) {
    int requiredMaids = int.tryParse(b['maidsCount']?.toString() ?? '1') ?? 1;
    List assigned = b['assignedMaidsList'] ?? [];

    return Column(
      children: [
        for (int i = 0; i < requiredMaids; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: _customDrop("اختر العاملة ${i + 1}", _maids, 'name', assigned.length > i ? assigned[i] : null, (v) {
              List newList = List.from(assigned);
              if (newList.length > i) {
                newList[i] = v;
              } else {
                while (newList.length < i) { newList.add(""); }
                newList.add(v);
              }
              // تم إلغاء استدعاء إرسال الإشعارات هنا، يتم التحديث في Firebase فقط
              _db.collection('bookings').doc(b['id']).update({'assignedMaidsList': newList, 'assignedMaid': newList[0]});
            }),
          ),
        _customDrop("اختر السائق/المركبة", _vehicles, 'driverName', b['assignedVehicle'], (v) {
           // تم إلغاء استدعاء إرسال الإشعارات هنا، يتم التحديث في Firebase فقط
          _db.collection('bookings').doc(b['id']).update({'assignedVehicle': v});
        }),
      ],
    );
  }

  Widget _customDrop(String label, List items, String field, String? current, Function(String) onSave) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15)),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        isExpanded: true, value: items.any((e) => e[field] == current) ? current : null,
        hint: Text(label, style: const TextStyle(fontSize: 11)),
        items: items.map((e) => DropdownMenuItem(value: e[field].toString(), child: Text(e[field].toString(), style: const TextStyle(fontSize: 11)))).toList(),
        onChanged: (v) => onSave(v!),
      )),
    );
  }

  Widget _buildProgressView(Map b) {
    String timeStr = _getTimer(b);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(25)),
      child: Column(children: [
        Text(timeStr, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        const SizedBox(height: 15),
        Row(children: [
          Expanded(child: _buildActionButton(b, "إنهاء الخدمة ✅", Colors.green, () => _showCompletionModal(b))),
          const SizedBox(width: 10),
          Expanded(child: _buildActionButton(b, "إيقاف مؤقت ⚠️", Colors.redAccent, () => _stopTask(b))),
        ]),
      ]),
    );
  }

  Widget _buildActionButton(Map b, String text, Color color, VoidCallback onTap) {
    return SizedBox(height: 50, child: ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: color, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 0),
      onPressed: onTap,
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    ));
  }

  void _startTask(Map b) async {
    int req = int.tryParse(b['maidsCount']?.toString() ?? '1') ?? 1;
    List assigned = b['assignedMaidsList'] ?? [];
    if (assigned.length < req || b['assignedVehicle'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ عين الطاقم والسائق أولاً")));
      return;
    }
    await _db.collection('bookings').doc(b['id']).update({'status': 'in-progress', 'actualStartedAt': FieldValue.serverTimestamp()});
    _sendNotifications(b, "بداية الزيارة 🚀", "بدأ فريقنا العمل الآن في منزلك.");
  }

  void _stopTask(Map b) {
    _showConfirmDialog("إيقاف المهمة", "هل تريد إعادة الطلب لقائمة الانتظار؟", () async {
      await _db.collection('bookings').doc(b['id']).update({'status': 'pending', 'actualStartedAt': null});
    });
  }

  void _confirmPaymentAndSend(Map b) async {
    await _db.collection('bookings').doc(b['id']).update({'paymentStatus': 'confirmed', 'status': 'pending'});
    _sendNotifications(b, "تأكيد الحجز ✅", "تم تأكيد دفعك وجدولة الزيارة بنجاح.");
  }

  void _undoConfirmPayment(Map b) {
    _db.collection('bookings').doc(b['id']).update({'paymentStatus': 'pending'});
  }

  void _deleteBooking(Map b) {
    _showConfirmDialog("حذف الطلب", "سيتم مسح البيانات نهائياً، هل أنت متأكد؟", () => _db.collection('bookings').doc(b['id']).delete());
  }

  void _showConfirmDialog(String title, String content, VoidCallback onConfirm) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text(title), content: Text(content),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("تراجع")),
        ElevatedButton(onPressed: () { onConfirm(); Navigator.pop(c); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("تأكيد")),
      ],
    ));
  }

  void _showCompletionModal(Map b) {
    _selectedRating = "ممتاز";
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(35))),
          padding: const EdgeInsets.all(25),
          child: Column(children: [
            const Text("إتمام المهمة والتقييم 🏁", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _ratingOption(setModalState, "ممتاز", Icons.sentiment_very_satisfied, Colors.green),
              _ratingOption(setModalState, "جيد", Icons.sentiment_satisfied, Colors.orange),
              _ratingOption(setModalState, "سيء", Icons.sentiment_very_dissatisfied, Colors.red),
            ]),
            const SizedBox(height: 20),
            const Text("توقيع العميل", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(child: Container(decoration: BoxDecoration(border: Border.all(color: Colors.grey[200]!), borderRadius: BorderRadius.circular(20)), 
              child: SfSignaturePad(key: _signaturePadKey))),
            const SizedBox(height: 20),
            _buildActionButton(b, "حفظ وإرسال للأرشيف ✅", Colors.blue, () async {
              await _db.collection('bookings').doc(b['id']).update({
                'status': 'completed', 
                'rating': _selectedRating, 
                'actualFinishedAt': FieldValue.serverTimestamp(),
                'completedBy': FirebaseAuth.instance.currentUser?.uid
              });
              _sendNotifications(b, "تمت المهمة بنجاح ✨", "شكراً لثقتك بنا، تم إتمام الخدمة وتقييمها بـ $_selectedRating.");
              Navigator.pop(context);
            }),
          ]),
        ),
      ),
    );
  }

  Widget _ratingOption(Function setModalState, String label, IconData icon, Color color) {
    bool isSelected = _selectedRating == label;
    return GestureDetector(
      onTap: () => setModalState(() => _selectedRating = label),
      child: Column(children: [
        Icon(icon, size: 45, color: isSelected ? color : Colors.grey[300]),
        Text(label, style: TextStyle(color: isSelected ? color : Colors.grey, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        Radio<String>(value: label, groupValue: _selectedRating, activeColor: color, onChanged: (v) => setModalState(() => _selectedRating = v!)),
      ]),
    );
  }

  Future<void> _sendNotifications(Map b, String title, String body) async {
    String userId = b['userId'] ?? "";
    if (userId.isNotEmpty) {
      final doc = await _db.collection('users').doc(userId).get();
      String? token = doc.data()?['fcmToken'];
      if (token != null) await FcmSender.sendNotification(token, title, body);
    }
  }
}
