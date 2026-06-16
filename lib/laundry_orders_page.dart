import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:syncfusion_flutter_signaturepad/signaturepad.dart';
// استيراد الملفات الجديدة للخدمات
import 'fcm_sender.dart'; 
// استيراد صفحة المكتملة
import 'completed_orders.dart'; 

class LaundryOrdersPage extends StatefulWidget {
  const LaundryOrdersPage({super.key});

  @override
  State<LaundryOrdersPage> createState() => _LaundryOrdersPageState();
}

class _LaundryOrdersPageState extends State<LaundryOrdersPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GlobalKey<SfSignaturePadState> _signaturePadKey = GlobalKey();

  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _allOrdersRaw = [];
  List<Map<String, dynamic>> _drivers = [];
  
  bool _isLoading = true;
  String _searchTerm = "";
  String _statusFilter = "all";
  String? _selectedDriver;
  String _adminRole = "loading"; 
  final String adminName = "إبراهيم عبدالله";

  @override
  void initState() {
    super.initState();
    _fetchAdminRole(); 
    _fetchInitialData();
  }

  Future<void> _fetchAdminRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      var doc = await _db.collection('users').doc(uid).get();
      if (mounted) {
        setState(() {
          _adminRole = doc.data()?['adminType'] ?? "staff";
          _applyFiltering(); // إعادة الفلترة بعد جلب الرتبة
        });
      }
    }
  }

  void _fetchInitialData() {
    _db.collection('laundry_orders')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      List<Map<String, dynamic>> raw = [];
      for (var doc in snap.docs) {
        var data = doc.data();
        if (data['status'] != 'completed') {
          raw.add({'id': doc.id, ...data});
        }
      }
      _allOrdersRaw = raw;
      _applyFiltering();
      if (mounted) setState(() => _isLoading = false);
    });

    _db.collection('vehicles').snapshots().listen((snap) {
      if (mounted) {
        setState(() {
          _drivers = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        });
      }
    });
  }

  void _applyFiltering() {
    setState(() {
      _orders = _allOrdersRaw.where((o) {
        // شرط جديد: إذا لم يكن super، لا تظهر البطاقات التي حالتها pending
        if (_adminRole != "super" && o['status'] == "pending") {
          return false;
        }

        bool matchesSearch = _searchTerm.isEmpty ||
            (o['userName'] ?? "").toString().toLowerCase().contains(_searchTerm.toLowerCase()) ||
            (o['orderNumber'] ?? "").toString().contains(_searchTerm);
        
        bool matchesStatus = _statusFilter == "all" || o['status'] == _statusFilter;
        
        return matchesSearch && matchesStatus;
      }).toList();
    });
  }

  Future<void> _sendNotification({required String userId, required String title, required String body, String target = 'all', String pieces = "0"}) async {
    // إرسال الإشعار للعميل صاحب الطلب
    await _db.collection('users').doc(userId).collection('notifications').add({
      'title': title,
      'body': body,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      'targetSection': 'all',
    });

    var userDoc = await _db.collection('users').doc(userId).get();
    String? userToken = userDoc.data()?['fcmToken'];
    if (userToken != null) {
      await FcmSender.sendNotification(userToken, title, body);
    }

    // جلب المسؤولين (مشرف الغسيل والمدير العام)
    final adminsSnap = await _db.collection('users')
        .where('adminType', whereIn: ['super', 'cleaning'])
        .get();
    
    for (var doc in adminsSnap.docs) {
      final data = doc.data();
      String adminType = data['adminType'] ?? "";
      
      await _db.collection('users').doc(doc.id).collection('notifications').add({
        'title': title,
        'body': body,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'targetSection': adminType == 'cleaning' ? 'cleaning' : 'super',
      });

      String? adminToken = data['fcmToken'];
      if (adminToken != null) {
        await FcmSender.sendNotification(adminToken, title, body);
      }
    }
  }

  void _confirmAction(String title, String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              onConfirm();
              Navigator.pop(context);
            }, 
            child: const Text("تأكيد", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
            _buildFilters(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _orders.isEmpty
                      ? const Center(child: Text("لا توجد طلبات نشطة حالياً 🕊️"))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _orders.length,
                          itemBuilder: (context, index) => _buildOrderCard(_orders[index]),
                        ),
            ),
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
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("إدارة الغسيل 🧼", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            Text("المشرف: $adminName", style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
          ]),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CompletedOrders()),
              );
            }, 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text("الأرشيف 📁", style: TextStyle(color: Colors.white, fontSize: 10)),
          )
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TextField(
            onChanged: (v) { _searchTerm = v; _applyFiltering(); },
            decoration: InputDecoration(
              hintText: "بحث باسم العميل أو رقم الطلب...",
              prefixIcon: const Icon(Icons.search, color: Colors.blue),
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _filterChip("الكل", "all"),
              _filterChip("بانتظار الاستلام", "pending"),
              _filterChip("قيد المعالجة", "processing"),
              _filterChip("في المغسلة", "received"),
            ],
          )
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    bool isSelected = _statusFilter == value;
    return GestureDetector(
      onTap: () { setState(() => _statusFilter = value); _applyFiltering(); },
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey[200]!),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> o) {
    String status = o['status'] ?? 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 15)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text("📅 طلب: ${_formatTimestamp(o['createdAt'])}", style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
          Row(children: [
            if (_adminRole == "super") ...[
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.orange, size: 18),
                onPressed: () => _confirmAction(
                  "إعادة تعيين الحالة", 
                  "هل تريد حقاً إعادة الطلب لحالة (بانتظار الاستلام)؟", 
                  () => _updateStatus(o['id'], "pending")
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 18),
                onPressed: () => _confirmAction(
                  "مسح الطلب", 
                  "سيتم حذف الطلب نهائياً من النظام، هل أنت متأكد؟", 
                  () => _db.collection('laundry_orders').doc(o['id']).delete()
                ),
              ),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: status == 'pending' ? Colors.orange[50] : (status == 'processing' ? Colors.teal[50] : Colors.blue[50]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_getStatusLabel(status), style: TextStyle(color: status == 'pending' ? Colors.orange[700] : (status == 'processing' ? Colors.teal[700] : Colors.blue[700]), fontSize: 8, fontWeight: FontWeight.bold)),
            ),
          ])
        ]),
        const SizedBox(height: 15),
        Row(children: [
          Expanded(child: Text(o['userName'] ?? "عميل", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
          _actionIcon(Icons.call, Colors.green, () => launchUrl(Uri.parse("tel:${o['contactPhone']}"))),
          const SizedBox(width: 8),
          _actionIcon(Icons.chat, Colors.teal, () => launchUrl(Uri.parse("https://wa.me/${o['contactPhone']}"))),
        ]),
        Text("#${o['orderNumber']} | ${o['contactPhone']}", style: const TextStyle(color: Colors.grey, fontSize: 10)),
        
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            _detailRow("نوع الخدمة:", _translateService(o['serviceType'])),
            _detailRow("الكمية | التكلفة:", "${o['pieces']} قطعة - ${o['totalPrice']} ج.س"),
            const Divider(),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("وصف العنوان", style: TextStyle(fontSize: 8, color: Colors.grey)),
                Text(o['addressDescription'] ?? "لا يوجد وصف", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ])),
              if (o['location'] != null)
                IconButton(
                  icon: const Icon(Icons.location_on, color: Colors.redAccent),
                  onPressed: () => launchUrl(Uri.parse("https://www.google.com/maps/search/?api=1&query=${o['location']['lat']},${o['location']['lng']}"))
                )
            ])
          ]),
        ),

        const SizedBox(height: 20),
        Column(
          children: [
            if (status == 'pending' && _adminRole == "super")
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[600],
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  onPressed: () {
                    _confirmAction(
                      "بدء المعالجة", 
                      "هل تريد إبلاغ العميل أن طلبه قيد المعالجة الآن؟", 
                      () async {
                        _updateStatus(o['id'], "processing");
                        await _sendNotification(
                          userId: o['userId'],
                          title: "طلبك قيد المراجعة ⚙️",
                          body: "العميل العزيز ${o['userName']}، طلبك رقم ${o['orderNumber']} تتم مراجعته الآن من قبل الإدارة.",
                          target: 'laundry',
                          pieces: o['pieces'].toString()
                        );
                      }
                    );
                  },
                  child: const Text("تأكيد أن الطلب في المراجعة ⚙️", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            if (status == 'pending' || status == 'processing')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[600],
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                    ),
                    onPressed: () {
                      _confirmAction(
                        "تأكيد الاستلام", 
                        "هل استلمت الملابس من العميل بنجاح؟", 
                        () async {
                          _updateStatus(o['id'], "received");
                          await _sendNotification(
                            userId: o['userId'],
                            title: "تم استلام ملابسك بنجاح 🧺",
                            body: "تم استلام الطلب رقم ${o['orderNumber']} بواسطة المشرف $adminName، وهو الآن في مرحلة الغسيل.",
                            target: 'laundry',
                            pieces: o['pieces'].toString()
                          );
                        }
                      );
                    },
                    child: const Text("تأكيد الاستلام 📦", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            if (status == 'received')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  onPressed: () => _showDeliveryModal(o),
                  child: const Text("تسليم نهائي للعميل 🚚", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        )
      ]),
    );
  }

  String _getStatusLabel(String status) {
    if (status == 'pending') return "بانتظار الاستلام";
    if (status == 'processing') return "قيد المعالجة";
    if (status == 'received') return "في المغسلة";
    return status;
  }

  void _updateStatus(String id, String status) async {
    await _db.collection('laundry_orders').doc(id).update({
      'status': status,
      'receivedAt': status == "received" ? FieldValue.serverTimestamp() : null,
    });
  }

  void _showDeliveryModal(Map o) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(40))),
      builder: (modalContext) => StatefulBuilder(builder: (context, setST) {
        return Padding(
          padding: EdgeInsets.fromLTRB(25, 25, 25, MediaQuery.of(context).viewInsets.bottom + 25),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text("تأكيد تسليم الطلب 🚚", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 20),
            
            DropdownButtonFormField<String>(
              decoration: InputDecoration(labelText: "السائق الموصل", border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))),
              initialValue: _selectedDriver,
              items: _drivers.map((d) => DropdownMenuItem(value: d['driverName'].toString(), child: Text(d['driverName']))).toList(),
              onChanged: (v) => setST(() => _selectedDriver = v),
            ),

            const SizedBox(height: 20),
            const Text("توقيع العميل المستلم ✍️", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            Container(
              height: 150, decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(20)),
              child: SfSignaturePad(key: _signaturePadKey),
            ),

            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              onPressed: () {
                if (_selectedDriver == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى اختيار السائق أولاً")));
                  return;
                }
                _confirmAction(
                  "إنهاء الطلب", 
                  "هل أنت متأكد من إرسال هذا الطلب للأرشيف؟", 
                  () async {
                    final image = await _signaturePadKey.currentState!.toImage();
                    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
                    if (bytes == null) return;
                    String base64Sig = "data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}";

                    await _db.collection('laundry_orders').doc(o['id']).update({
                      'status': 'completed',
                      'customerSignature': base64Sig,
                      'deliveredByDriver': _selectedDriver,
                      'finalizedByAdmin': adminName,
                      'actualDeliveredAt': FieldValue.serverTimestamp(),
                      'isRated': false,
                    });

                    await _sendNotification(
                      userId: o['userId'],
                      title: "تم تسليم طلبك بنجاح ✅",
                      body: "العميل العزيز ${o['userName']}، نحن ممتنون جداً لثقتك بنا وتعاملك معنا. تم تسليم ملابسك بنجاح، نتطلع لخدمتك دائماً ✨",
                      target: 'laundry',
                      pieces: o['pieces'].toString()
                    );
                    
                    if (modalContext.mounted) Navigator.pop(modalContext);
                  }
                );
              },
              child: const Text("إنهاء وإرسال للأرشيف", style: TextStyle(color: Colors.white)),
            )
          ]),
        );
      }),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _actionIcon(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(onTap: onTap, child: CircleAvatar(backgroundColor: color.withAlpha(25), child: Icon(icon, color: color, size: 18)));
  }

  String _translateService(String? type) {
    if (type == 'wash_iron') return "غسيل ومكواة 🧺";
    if (type == 'iron_only') return "مكواة فقط 💨";
    return "غسيل فقط 💧";
  }

  String _formatTimestamp(dynamic t) {
    if (t == null) return "---";
    if (t is Timestamp) return DateFormat('dd/MM | hh:mm a').format(t.toDate());
    return t.toString();
  }
}
