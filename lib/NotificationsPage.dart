import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final String? _userId = FirebaseAuth.instance.currentUser?.uid;
  String? _adminType; 

  @override
  void initState() {
    super.initState();
    _fetchAdminType(); 
    // ملاحظة: لا نستدعي _markAllAsRead هنا مباشرة للسماح للمستخدم برؤية التمييز البصري أولاً
  }

  Future<void> _fetchAdminType() async {
    if (_userId == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(_userId).get();
    if (mounted) {
      setState(() {
        _adminType = userDoc.data()?['adminType'];
      });
    }
  }

  // دالة لتحديث إشعار واحد كـ "مقروء" عند الضغط عليه أو التفاعل معه
  Future<void> _markAsRead(String docId) async {
    if (_userId == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_userId)
        .collection('notifications')
        .doc(docId)
        .update({'isRead': true});
  }

  Future<void> _markAllAsRead() async {
    if (_userId == null) return;
    
    final querySnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(_userId)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .get();

    WriteBatch batch = FirebaseFirestore.instance.batch();
    for (var doc in querySnapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
    
    if(mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم تحديد الكل كمقروء"), duration: Duration(seconds: 1))
      );
    }
  }

  Future<void> _deleteAllNotifications() async {
    if (_userId == null) return;

    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("مسح السجل", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: const Text("سيتم حذف جميع الإشعارات نهائياً من حسابك."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("إلغاء")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("حذف الكل", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      final snapshots = await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .collection('notifications')
          .get();
      
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshots.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text("التنبيهات", 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Cairo')),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: const Color(0xFF1E293B),
        actions: [
          if (_userId != null) ...[
             IconButton(
              icon: const Icon(Icons.done_all, color: Colors.blue),
              onPressed: _markAllAsRead,
              tooltip: "تحديد الكل كمقروء",
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _deleteAllNotifications,
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: _userId == null
          ? const Center(child: Text("الرجاء تسجيل الدخول"))
          : StreamBuilder<QuerySnapshot>(
              stream: _getFilteredStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    return _buildNotificationCard(doc.id, data);
                  },
                );
              },
            ),
    );
  }

  Stream<QuerySnapshot> _getFilteredStream() {
    // الاستعلام يركز فقط على إشعارات المستخدم الحالي (سواء كان عميل أو موظف)
    // الفلترة تتم حسب targetSection الذي نحدده عند إرسال الإشعار
    return FirebaseFirestore.instance
        .collection('users')
        .doc(_userId)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Widget _buildNotificationCard(String docId, Map<String, dynamic> data) {
    bool isRead = data['isRead'] ?? false;
    DateTime? date = (data['timestamp'] as Timestamp?)?.toDate();
    String timeStr = date != null ? DateFormat('hh:mm a | yyyy/MM/dd').format(date) : "";

    return GestureDetector(
      onTap: () => _markAsRead(docId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : Colors.blue.withOpacity(0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isRead ? Colors.transparent : Colors.blue.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // أيقونة الحالة (تتغير إذا كان مقروء أم لا)
            CircleAvatar(
              backgroundColor: isRead ? Colors.grey[100] : Colors.blue[100],
              radius: 22,
              child: Icon(
                isRead ? Icons.notifications_none : Icons.notifications_active,
                color: isRead ? Colors.grey : Colors.blue,
                size: 20,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        data['title'] ?? "تنبيه",
                        style: TextStyle(
                          fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                          fontSize: 15,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                        )
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    data['body'] ?? "",
                    style: TextStyle(fontSize: 13, color: Colors.blueGrey[600], height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    timeStr,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text("سجل التنبيهات فارغ", style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
