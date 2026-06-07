import 'package:flutter/material.dart';
import 'map_view_page.dart'; // استيراد صفحة الخريطة لضمان عمل التنقل

class ServiceSelectionPage extends StatelessWidget {
  const ServiceSelectionPage({super.key});

  final List<String> professions = const [
    "كهربائي",
    "سباك (مواسيرجي)",
    "فني تكييف وتبريد",
    "توصيل طلبات (ركشة/موتر)",
    "ممرض / ممرضة",
    "فني غسالات",
    "ميكانيكي",
    "عامل مساعد"
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("اختر الحرفة المطلوبة",
            style: TextStyle(fontWeight: FontWeight.w900)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: professions.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MapViewPage(
                            serviceType: professions[
                                index]), // Ensure that serviceType parameter is correctly defined in MapViewPage
                      ),
                    ),
                    child: Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      child: Center(
                        child: Text(
                          professions[index],
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // زر "هل أنت صاحب حرفة"
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: InkWell(
                onTap: () => Navigator.pushNamed(context, '/manage'),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.grey.shade300, style: BorderStyle.solid),
                  ),
                  child: const Column(
                    children: [
                      Text("هل أنت صاحب حرفة؟ 🛠️",
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      Text("انقر هنا لإضافة حرفتك والظهور على الخريطة",
                          style: TextStyle(fontSize: 10, color: Colors.blue)),
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
