import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui; 

class MonthlyContractsCompletedPage extends StatefulWidget {
  final String adminType;
  const MonthlyContractsCompletedPage({super.key, this.adminType = 'super'});

  @override
  State<MonthlyContractsCompletedPage> createState() => _MonthlyContractsCompletedPageState();
}

class _MonthlyContractsCompletedPageState extends State<MonthlyContractsCompletedPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _loading = true;
  List<Map<String, dynamic>> _completedVisits = [];
  DateTime _selectedDate = DateTime.now();
  bool _isFiltered = false;

  @override
  void initState() {
    super.initState();
    _fetchCompletedVisits();
  }

  // تصحيح جلب الزيارات من كولكشن contracts بدلاً من bookings
  Future<void> _fetchCompletedVisits() async {
    if (mounted) setState(() => _loading = true);

    try {
      List<Map<String, dynamic>> allVisits = [];
      
      // جلب جميع المستندات من كولكشن contracts
      var contractsSnap = await _db.collection('contracts').get();

      for (var contractDoc in contractsSnap.docs) {
        var contractData = contractDoc.data();
        
        // جلب الزيارات المكتملة من المجموعة الفرعية visits داخل كل عقد
        var visitsSnap = await _db.collection('contracts') // التصحيح هنا
            .doc(contractDoc.id)
            .collection('visits')
            .where('status', isEqualTo: 'completed')
            .get();

        for (var visitDoc in visitsSnap.docs) {
          var vData = visitDoc.data();
          allVisits.add({
            ...vData,
            'visitId': visitDoc.id,
            'contractId': contractDoc.id,
            'clientName': contractData['fullName'] ?? "بدون اسم",
            'phone': contractData['phone'] ?? "",
            'region': contractData['region'] ?? "غير محدد",
            'address': contractData['address'] ?? "بدون عنوان",
            'contractNumber': contractData['contractId'] ?? "---",
            // التأكد من وجود حقل التاريخ للترتيب، نستخدم visitDate إذا لم يوجد completedAt
            'sortDate': vData['completedAt'] ?? vData['visitDate'] ?? Timestamp.now(),
          });
        }
      }

      // فرز الزيارات حسب التاريخ الأحدث
      allVisits.sort((a, b) {
        Timestamp t1 = a['sortDate'] is Timestamp ? a['sortDate'] : Timestamp.now();
        Timestamp t2 = b['sortDate'] is Timestamp ? b['sortDate'] : Timestamp.now();
        return t2.compareTo(t1);
      });

      if (mounted) {
        setState(() {
          _completedVisits = allVisits;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching visits: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> displayedVisits = _isFiltered 
      ? _completedVisits.where((v) {
          var dateValue = v['sortDate'];
          if (dateValue == null) return false;
          DateTime date = (dateValue as Timestamp).toDate();
          return DateFormat('yyyy-MM-dd').format(date) == DateFormat('yyyy-MM-dd').format(_selectedDate);
        }).toList()
      : _completedVisits;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text("الأرشيف - الزيارات المكتملة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(onPressed: _fetchCompletedVisits, icon: const Icon(Icons.refresh))
        ],
      ),
      body: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Column(
          children: [
            _buildFilterHeader(),
            Expanded(
              child: _loading 
                ? const Center(child: CircularProgressIndicator())
                : displayedVisits.isEmpty 
                  ? const Center(child: Text("لا توجد زيارات مكتملة حالياً"))
                  : ListView.builder(
                      padding: const EdgeInsets.all(15),
                      itemCount: displayedVisits.length,
                      itemBuilder: (context, index) => _buildVisitCard(displayedVisits[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterHeader() {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.white,
      child: Row(
        children: [
          const Icon(Icons.filter_list, color: Colors.blue),
          const SizedBox(width: 10),
          const Text("تصفية حسب التاريخ:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          ActionChip(
            label: Text(_isFiltered ? DateFormat('yyyy-MM-dd').format(_selectedDate) : "الكل"),
            onPressed: () async {
              final d = await showDatePicker(
                context: context, 
                initialDate: _selectedDate, 
                firstDate: DateTime(2024), 
                lastDate: DateTime.now()
              );
              if (d != null) {
                setState(() {
                  _selectedDate = d;
                  _isFiltered = true;
                });
              }
            },
          ),
          if (_isFiltered) IconButton(onPressed: () => setState(() => _isFiltered = false), icon: const Icon(Icons.close, size: 18)),
        ],
      ),
    );
  }

  Widget _buildVisitCard(Map v) {
    String formattedDate = "غير محدد";
    if (v['sortDate'] != null) {
      formattedDate = DateFormat('yyyy-MM-dd | hh:mm a').format((v['sortDate'] as Timestamp).toDate());
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(v['clientName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(v['contractNumber'], style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.location_on, size: 14, color: Colors.grey),
              const SizedBox(width: 5),
              Text("${v['region']} - ", style: const TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
              Expanded(child: Text(v['address'], style: const TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const Divider(height: 25),
          Row(
            children: [
              _miniDetail(Icons.person, v['maid'] ?? "---", Colors.orange),
              const SizedBox(width: 10),
              _miniDetail(Icons.local_shipping, v['vehicle'] ?? "---", Colors.blue),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _miniDetail(Icons.star, "التقييم: ${v['rating'] ?? 'بدون'}", Colors.green),
              const Spacer(),
              Text(formattedDate, style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          ),
          if (widget.adminType == 'super') ...[
            const Divider(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _confirmDelete(v),
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
                  label: const Text("حذف السجل", style: TextStyle(color: Colors.red, fontSize: 11)),
                )
              ],
            )
          ]
        ],
      ),
    );
  }

  Widget _miniDetail(IconData icon, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.1))),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(Map visit) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("حذف السجل"),
        content: const Text("هل أنت متأكد من حذف سجل هذه الزيارة نهائياً؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.collection('contracts') // تم تصحيح المسار هنا أيضاً
                  .doc(visit['contractId'])
                  .collection('visits')
                  .doc(visit['visitId'])
                  .delete();
              Navigator.pop(context);
              _fetchCompletedVisits();
            },
            child: const Text("حذف", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
