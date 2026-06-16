import 'package:flutter/material.dart';
import 'app_constants.dart';
import 'map_view_page.dart'; 
import 'manage_handyman_page.dart';

class HandymanHubPage extends StatefulWidget {
  const HandymanHubPage({super.key});

  @override
  State<HandymanHubPage> createState() => _HandymanHubPageState();
}

class _HandymanHubPageState extends State<HandymanHubPage> {
  String? _selectedService;

  // دالة مساعدة للحصول على الأيقونة بناءً على اسم الحرفة
  IconData _getIconForService(String profession) {
    if (profession.contains("كهربائي")) return Icons.bolt;
    if (profession.contains("سباك")) return Icons.plumbing;
    if (profession.contains("تكييف")) return Icons.ac_unit;
    if (profession.contains("توصيل")) return Icons.delivery_dining;
    if (profession.contains("ممرض")) return Icons.medical_services;
    if (profession.contains("غسالات")) return Icons.local_laundry_service;
    if (profession.contains("ميكانيكي")) return Icons.home_repair_service;
    if (profession.contains("نقاش")) return Icons.format_paint;
    if (profession.contains("نجار")) return Icons.handyman;
    if (profession.contains("ستالايت")) return Icons.settings_input_antenna;
    if (profession.contains("مبلط")) return Icons.grid_view;
    if (profession.contains("حداد")) return Icons.hardware;
    if (profession.contains("بناء")) return Icons.foundation;
    if (profession.contains("طباخ")) return Icons.restaurant;
    if (profession.contains("حلاق")) return Icons.content_cut;
    if (profession.contains("غسيل عربات")) return Icons.local_car_wash;
    return Icons.construction; // أيقونة افتراضية
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _selectedService == null 
          ? _buildSelectionScreen() 
          : Stack(
              children: [
                MapViewPage(serviceType: _selectedService!),
                _buildBackOverlay(),
              ],
            ),
    );
  }

  Widget _buildSelectionScreen() {
    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(25.0),
            child: Text("ما هي الخدمة التي تحتاجها؟", 
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, 
                childAspectRatio: 1.1, // تم تعديل النسبة لتناسب الأيقونة مع النص
                crossAxisSpacing: 15, 
                mainAxisSpacing: 15
              ),
              itemCount: AppConstants.professionsList.length,
              itemBuilder: (context, index) => _buildServiceCard(AppConstants.professionsList[index]),
            ),
          ),
          _buildManageEntry(),
        ],
      ),
    );
  }

  Widget _buildServiceCard(String title) {
    return InkWell(
      onTap: () => setState(() => _selectedService = title),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(25), 
          border: Border.all(color: Colors.grey.shade100), 
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]
        ),
        child: Column( // تم تغيير Center إلى Column لإضافة الأيقونة فوق النص
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getIconForService(title),
              size: 40,
              color: Colors.blue.shade700,
            ),
            const SizedBox(height: 10),
            Text(
              title, 
              textAlign: TextAlign.center, 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManageEntry() {
    return Padding(
      padding: const EdgeInsets.all(25.0),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageHandymanPage())),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(20), 
            border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid)
          ),
          child: const Column(
            children: [
              Text("هل أنت صاحب حرفة؟ 🛠️", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              Text("أضف خدمتك لتظهر للزبائن في منطقتك", 
                  style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackOverlay() {
    return Positioned(
      top: 50,
      right: 20,
      child: InkWell(
        onTap: () => setState(() => _selectedService = null),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(15), 
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]
          ),
          child: Text("↩️ تغيير الحرفة ($_selectedService)", 
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
        ),
      ),
    );
  }
}
