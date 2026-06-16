import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart'; // إضافة مكتبة جلب العناوين النصية من الإحداثيات
import 'dart:math';
import 'package:intl/intl.dart'; 
// استيراد خدمة الإشعارات
import 'notification_service.dart';

class LaundryCheckoutPage extends StatefulWidget {
  const LaundryCheckoutPage({super.key});

  @override
  State<LaundryCheckoutPage> createState() => _LaundryCheckoutPageState();
}

class _LaundryCheckoutPageState extends State<LaundryCheckoutPage> {
  // --- States ---
  int _step = 1;
  bool _isLoading = true;
  bool _isSubmitting = false;

  Map<String, double> _prices = {'wash': 0, 'iron': 0, 'ironOnly': 0};
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  
  // حقل المنطقة الجديد
  String? _selectedRegion;
  final List<String> _regions = ["أمدرمان", "بحري", "شرق النيل"];

  int _pieces = 12;
  String _serviceType = "wash_only";
  String _locationStatus = "جاري تحديد موقعك...";
  Map<String, double>? _locationCoords;

  // تعريف منسق الأرقام الإنجليزية كمتغير ثابت للاستخدام في الصفحة
  final NumberFormat _engFormat = NumberFormat('#,###.##', 'en');

  @override
  void initState() {
    super.initState();
    _initData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _determinePosition();
    });
  }

  // --- Logic ---
  Future<void> _initData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    try {
      // جلب الأسعار
      final priceDoc = await FirebaseFirestore.instance.collection('settings').doc('laundry_prices').get();
      if (priceDoc.exists) {
        setState(() {
          _prices = {
            'wash': double.tryParse(priceDoc.data()?['wash'].toString() ?? "0") ?? 0,
            'iron': double.tryParse(priceDoc.data()?['iron'].toString() ?? "0") ?? 0,
            'ironOnly': double.tryParse(priceDoc.data()?['ironOnly'].toString() ?? "0") ?? 0,
          };
        });
      }

      // جلب بيانات المستخدم (بما في ذلك المنطقة)
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        setState(() {
          _nameController.text = data?['fullName'] ?? "";
          _phoneController.text = data?['phone'] ?? "";
          _addressController.text = data?['address'] ?? "";
          
          // التحقق من وجود المنطقة في بيانات المستخدم
          if (data != null && data['region'] != null && _regions.contains(data['region'])) {
            _selectedRegion = data['region'];
          }

          if (data != null && data['latitude'] != null && data['longitude'] != null) {
            _locationCoords = {
              'lat': (data['latitude'] as num).toDouble(),
              'lng': (data['longitude'] as num).toDouble(),
            };
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading data: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _locationStatus = "GPS معطل ⚠️");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition();
      
      String areaName = "";
      try {
        // ضبط لغة جلب البيانات جلوبال قبل الاستدعاء تماشياً مع إصدار geocoding 3.0.0
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude, 
          position.longitude
        );
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          areaName = place.subLocality ?? "";
          if (areaName.isEmpty) {
            areaName = place.thoroughfare ?? "";
          }
          if (areaName.isEmpty) {
            areaName = place.name ?? "";
          }
        }
      } catch (e) {
        debugPrint("Geocoding Error: $e");
      }

      if (mounted) {
        setState(() {
          _locationCoords = {'lat': position.latitude, 'lng': position.longitude};
          _locationStatus = "تم تحديد موقعك الحالي ✅";
          if (areaName.isNotEmpty) {
            _addressController.text = areaName;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _locationStatus = _locationCoords != null ? "تم استخدام موقعك المسجل 🏠" : "يرجى وصف العنوان بدقة ⚠️");
      }
    }
  }

  double get _totalPrice {
    double pricePerPiece = _prices['wash']!;
    if (_serviceType == "wash_iron") pricePerPiece = _prices['iron']!;
    if (_serviceType == "iron_only") pricePerPiece = _prices['ironOnly']!;
    return _pieces * pricePerPiece;
  }

  void _handleNextStep() {
    if (_step == 1) {
      if (_nameController.text.isEmpty || _phoneController.text.isEmpty) {
        _showError("⚠️ يرجى إدخال الاسم ورقم الهاتف");
        return;
      }
      if (_pieces < 12) {
        _showError("عذراً، أقل عدد للطلب هو 12 قطعة");
        return;
      }
      setState(() => _step = 2);
    } else if (_step == 2) {
      if (_selectedRegion == null) {
        _showError("⚠️ يرجى اختيار المنطقة");
        return;
      }
      if (_addressController.text.isEmpty) {
        _showError("⚠️ يرجى كتابة وصف العنوان بدقة");
        return;
      }
      setState(() => _step = 3);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submitOrder() async {
    setState(() => _isSubmitting = true);
    final user = FirebaseAuth.instance.currentUser;

    try {
      await FirebaseFirestore.instance.collection('laundry_orders').add({
        'orderNumber': 1000 + Random().nextInt(9000),
        'userId': user?.uid,
        'userName': _nameController.text,
        'pieces': _pieces,
        'serviceType': _serviceType,
        'totalPrice': _totalPrice,
        'contactPhone': _phoneController.text,
        'region': _selectedRegion, // حفظ المنطقة المختارة
        'addressDescription': _addressController.text,
        'location': _locationCoords,
        'status': "pending",
        'isRated': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      NotificationService.showNotification(
        "تم استلام طلب الغسيل 🧺",
        "تم تسجيل طلبك (عدد القطع: $_pieces) بنجاح."
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🚀 تم إرسال طلب الغسيل بنجاح!")));
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) _showError("❌ فشل إرسال الطلب");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF1E293B))));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildCurrentStepView(),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_step == 1 ? "بيانات الطلب 🧺" : _step == 2 ? "موقع الاستلام 📍" : "تأكيد الطلب ⚙️", 
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.home, color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _stepIndicator(1),
              const SizedBox(width: 8),
              _stepIndicator(2),
              const SizedBox(width: 8),
              _stepIndicator(3),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepIndicator(int s) {
    return Expanded(
      child: Container(
        height: 6,
        decoration: BoxDecoration(
          color: _step >= s ? Colors.blue : Colors.white12,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_step) {
      case 1: return _buildStep1();
      case 2: return _buildStep2();
      case 3: return _buildStep3();
      default: return _buildStep1();
    }
  }

  // --- الخطوة 1: الغسيل والبيانات الشخصية ---
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _serviceOption("غسيل فقط", "wash_only", _prices['wash']!),
            const SizedBox(width: 10),
            _serviceOption("مكواة فقط", "iron_only", _prices['ironOnly']!),
            const SizedBox(width: 10),
            _serviceOption("غسيل ومكواة", "wash_iron", _prices['iron']!),
          ],
        ),
        const SizedBox(height: 20),
        _buildCounterCard(),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.grey[200]!)),
          child: Column(
            children: [
              _inputField("الاسم الكامل", _nameController, Icons.person),
              const SizedBox(height: 15),
              _inputField("رقم الهاتف", _phoneController, Icons.phone, isPhone: true),
            ],
          ),
        ),
      ],
    );
  }

  // --- الخطوة 2: الموقع والمنطقة ---
  Widget _buildStep2() {
    return Column(
      children: [
        const SizedBox(height: 10),
        _locationStatusBox(),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.grey[200]!)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("اختر المنطقة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 10),
              _buildRegionDropdown(),
              const SizedBox(height: 20),
              const Text("وصف العنوان بالتفصيل", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 10),
              _inputField("اكتب العنوان (المنزل، الشارع، المعلم القريب)...", _addressController, Icons.map, maxLines: 4),
            ],
          ),
        ),
      ],
    );
  }

  // --- الخطوة 3: آلية التنفيذ ---
  Widget _buildStep3() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(35), border: Border.all(color: Colors.grey[100]!)),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: const BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.vertical(top: Radius.circular(34))),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text("مراجعة الطلب 🧾", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), Icon(Icons.check_circle, color: Colors.white)],
                ),
              ),
              _mechanismTile("١. المنطقة والوجهة", "منطقتك: ${_selectedRegion ?? 'غير محدد'}", Colors.blue),
              _mechanismTile("٢. تفاصيل الاستلام", "سيتم التواصل مع المالك: ${_nameController.text}", Colors.green),
              _mechanismTile("٣. الدفع والرسوم", "سيتم دفع الرسوم عند الاستلام النهائي.", Colors.amber),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // تم تطبيق تنسيق الفاصلة العشرية الإنجليزية هنا
                      Text("${_engFormat.format(_totalPrice)} ج.س", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFE53E3E))),
                      const Text("الإجمالي (شامل خدمة التوصيل )", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  // --- UI Components ---
  Widget _buildRegionDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedRegion,
          hint: const Text("اختر منطقتك", style: TextStyle(fontSize: 12)),
          isExpanded: true,
          items: _regions.map((String region) {
            return DropdownMenuItem<String>(
              value: region,
              child: Text(region, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            );
          }).toList(),
          onChanged: (newValue) {
            setState(() {
              _selectedRegion = newValue;
            });
          },
        ),
      ),
    );
  }

  Widget _buildCounterCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(30), border: const Border(bottom: BorderSide(color: Colors.blue, width: 4))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("عدد القطع", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
              Text("الحد الأدنى 12 قطعة", style: TextStyle(color: Colors.blueAccent, fontSize: 9)),
            ],
          ),
          Row(
            children: [
              _counterBtn("-", () => setState(() => _pieces = max(12, _pieces - 1))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Text("$_pieces", style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
              ),
              _counterBtn("+", () => setState(() => _pieces++)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _serviceOption(String label, String id, double price) {
    bool isSelected = _serviceType == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _serviceType = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue[50] : Colors.white,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: isSelected ? Colors.blue : Colors.white, width: 2),
          ),
          child: Column(
            children: [
              Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
              // تم تطبيق التنسيق هنا أيضاً لضمان اتساق الأسعار في الواجهة
              Text(_engFormat.format(price), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _counterBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: label == "+" ? Colors.white : Colors.white10, borderRadius: BorderRadius.circular(15)),
        child: Center(child: Text(label, style: TextStyle(color: label == "+" ? const Color(0xFF1E293B) : Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
      ),
    );
  }

  Widget _inputField(String hint, TextEditingController controller, IconData icon, {bool isPhone = false, int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      textAlign: isPhone ? TextAlign.left : TextAlign.right,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: Colors.blue),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
      ),
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
    );
  }

  Widget _locationStatusBox() {
    bool hasCoords = _locationCoords != null;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: hasCoords ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hasCoords ? Colors.green[100]! : Colors.red[100]!),
      ),
      child: Row(
        children: [
          Icon(Icons.my_location, color: hasCoords ? Colors.green : Colors.red),
          const SizedBox(width: 12),
          Expanded(child: Text(_locationStatus, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: hasCoords ? Colors.green[700]! : Colors.red[700]!))),
          if (!hasCoords) TextButton(onPressed: _determinePosition, child: const Text("تحديث"))
        ],
      ),
    );
  }

  Widget _mechanismTile(String title, String desc, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 4, height: 40, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(40))),
      child: Row(
        children: [
          if (_step > 1)
            Container(
              margin: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)),
              child: IconButton(
                onPressed: () => setState(() => _step--),
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              ),
            ),
          Expanded(
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : (_step < 3 ? _handleNextStep : _submitOrder),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: _isSubmitting 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(_step < 3 ? "الخطوة التالية ➡️" : "تأكيد وإرسال الطلب ✅", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
