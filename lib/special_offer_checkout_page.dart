import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

import 'notification_service.dart';

class SpecialOfferCheckoutPage extends StatefulWidget {
  final String packageId;

  const SpecialOfferCheckoutPage({super.key, required this.packageId});

  @override
  State<SpecialOfferCheckoutPage> createState() => _SpecialOfferCheckoutPageState();
}

class _SpecialOfferCheckoutPageState extends State<SpecialOfferCheckoutPage> {
  int _currentStep = 1;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isLocating = false;
  bool _hasAcceptedTerms = false;

  Map<String, dynamic>? _packageData;
  double _baseOfferPrice = 0; // سعر العرض الأساسي للعاملة الواحدة
  double _originalPrice = 0; 
  int _discountPercent = 0;
  bool _isDayFull = false;
  int _totalMaidsInSystem = 0;
  List<String> _adminFullDays = [];
  
  // إضافة متغير عدد العاملات
  int _selectedMaidsCount = 1;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  
  String _selectedGender = "female";
  String _selectedShift = "morning";
  String? _selectedRegion;
  String _selectedDate = "";
  Position? _currentPosition;
  
  final List<String> _regions = ["أم درمان", "بحري", "شرق النيل", "الخرطوم"];

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    _handleAutoLocation();
  }

  Future<void> _fetchInitialData() async {
    try {
      final pkgSnap = await FirebaseFirestore.instance.collection('packages').doc(widget.packageId).get();
      final settingsSnap = await FirebaseFirestore.instance.collection('settings').doc('cleaning_prices').get();
      final maidsSnap = await FirebaseFirestore.instance.collection('maids').get();
      
      _totalMaidsInSystem = maidsSnap.size;

      FirebaseFirestore.instance.collection('settings').doc('availability').snapshots().listen((snap) {
        if (snap.exists && mounted) {
          setState(() => _adminFullDays = List<String>.from(snap.data()?['fullDays'] ?? []));
        }
      });

      if (pkgSnap.exists) {
        _packageData = pkgSnap.data();
        _baseOfferPrice = double.tryParse(_packageData!['price']?.toString() ?? "0") ?? 0;
        
        if (settingsSnap.exists) {
          final sData = settingsSnap.data()!;
          _packageData!['totalHours'] = sData['single_hours']?.toString() ?? "5";
          _originalPrice = double.tryParse(sData['single_price']?.toString() ?? "0") ?? 0;
          
          if (_originalPrice > _baseOfferPrice && _originalPrice > 0) {
            _discountPercent = (((_originalPrice - _baseOfferPrice) / _originalPrice) * 100).round();
          }
        }
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          setState(() {
            _nameController.text = userDoc.data()?['fullName'] ?? "";
            _phoneController.text = userDoc.data()?['phone'] ?? "";
            _addressController.text = userDoc.data()?['address'] ?? "";
            _selectedRegion = userDoc.data()?['region'];
          });
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Future<void> _handleAutoLocation() async {
    setState(() => _isLocating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = position;
        _addressController.text = _addressController.text.replaceAll(RegExp(r'📍 الموقع محدد عبر GPS.*'), '');
        _addressController.text += "\n📍 الموقع محدد عبر GPS (${position.latitude}, ${position.longitude})";
        _isLocating = false;
      });
    } catch (e) {
      setState(() => _isLocating = false);
    }
  }

  Future<void> _checkAvailability(String date) async {
    if (_adminFullDays.contains(date)) {
      setState(() => _isDayFull = true);
      return;
    }
    final q = await FirebaseFirestore.instance
        .collection('bookings')
        .where('startDate', isEqualTo: date)
        .where('status', isNotEqualTo: 'cancelled')
        .get();
    
    int bookedMaids = 0;
    for (var doc in q.docs) {
      bookedMaids += int.tryParse(doc.data()['maidsCount']?.toString() ?? "1") ?? 1;
    }

    setState(() => _isDayFull = (bookedMaids + _selectedMaidsCount) > _totalMaidsInSystem);
  }

  Future<void> _handleSubmit() async {
    if (_isDayFull) return;
    setState(() => _isSubmitting = true);

    double finalPrice = _baseOfferPrice * _selectedMaidsCount;

    try {
      final user = FirebaseAuth.instance.currentUser;
      
      await FirebaseFirestore.instance.collection('bookings').add({
        'fullName': _nameController.text,
        'phone': _phoneController.text,
        'gender': _selectedGender,
        'shift': _selectedShift,
        'maidsCount': _selectedMaidsCount,
        'startDate': _selectedDate,
        'region': _selectedRegion,
        'locationText': _addressController.text,
        'locationCoords': _currentPosition != null ? {'lat': _currentPosition!.latitude, 'lng': _currentPosition!.longitude} : null,
        'price': finalPrice.toStringAsFixed(0),
        'packageName': "عرض خاص: ${_packageData?['name']} ($_selectedMaidsCount عاملة)",
        'totalHours': _packageData?['totalHours'],
        'userId': user!.uid,
        'category': 'special_offer',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      NotificationService.showNotification("تم استلام طلب العرض ✨", "موعدك: $_selectedDate. عدد العاملات: $_selectedMaidsCount.");

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🚀 تم حجز العرض بنجاح!")));
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildStepContent(),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 20, right: 20, bottom: 30),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("عرض المميزين ✨", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          Text("${_packageData?['name']}", style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            children: [
              _progressLine(true),
              const SizedBox(width: 10),
              _progressLine(_currentStep >= 2),
              const SizedBox(width: 10),
              _progressLine(_currentStep == 3),
            ],
          )
        ],
      ),
    );
  }

  Widget _progressLine(bool active) => Expanded(child: Container(height: 4, decoration: BoxDecoration(color: active ? Colors.blue : Colors.white12, borderRadius: BorderRadius.circular(10))));

  Widget _buildStepContent() {
    if (_currentStep == 1) return _buildStep1();
    if (_currentStep == 2) return _buildStep2();
    return _buildStep3Terms();
  }

  Widget _buildStep1() {
    return Column(
      children: [
        _buildPriceCard(),
        const SizedBox(height: 20),
        _buildMaidCounter(),
        const SizedBox(height: 15),
        _buildGenderToggle(),
        const SizedBox(height: 15),
        _buildTextField(_nameController, "الاسم الكامل", Icons.person),
        const SizedBox(height: 15),
        _buildTextField(_phoneController, "رقم الهاتف", Icons.phone, isPhone: true),
        const SizedBox(height: 15),
        _buildDatePicker(),
      ],
    );
  }

  Widget _buildPriceCard() {
    double totalPrice = _baseOfferPrice * _selectedMaidsCount;
    double totalOriginal = _originalPrice * _selectedMaidsCount;

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(35), border: Border.all(color: Colors.black12)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("تكلفة العرض الإجمالية", style: TextStyle(color: Colors.grey, fontSize: 10)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("${totalPrice.toStringAsFixed(0)} ج.س", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
                      const SizedBox(width: 10),
                      if (_discountPercent > 0)
                        Text(
                          "${totalOriginal.toInt()} ج.س",
                          style: const TextStyle(fontSize: 14, color: Colors.grey, decoration: TextDecoration.lineThrough, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ],
              ),
              if (_discountPercent > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Text("توفير $_discountPercent%", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
            ],
          ),
          const Divider(height: 30),
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 16, color: Colors.blue),
              const SizedBox(width: 5),
              Text("مدة الزيارة: ${_packageData?['totalHours']} ساعات لكل عاملة", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue)),
              const Spacer(),
              const Text("سعر شامل الضريبة ✨", style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMaidCounter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.black12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("عدد العاملات (أقصى 3)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Row(
            children: [
              _counterBtn(Icons.remove, () {
                if (_selectedMaidsCount > 1) {
                  setState(() => _selectedMaidsCount--);
                  if (_selectedDate.isNotEmpty) _checkAvailability(_selectedDate);
                }
              }),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Text("$_selectedMaidsCount", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
              ),
              _counterBtn(Icons.add, () {
                if (_selectedMaidsCount < 3) {
                  setState(() => _selectedMaidsCount++);
                  if (_selectedDate.isNotEmpty) _checkAvailability(_selectedDate);
                }
              }),
            ],
          )
        ],
      ),
    );
  }

  Widget _counterBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.blue, size: 20),
      ),
    );
  }

  Widget _buildStep2() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(35), border: Border.all(color: Colors.black12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("📍 موقع التنفيذ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 20),
              _gpsButton(),
              const SizedBox(height: 20),
              _buildRegionDropdown(),
              const SizedBox(height: 20),
              _buildTextField(_addressController, "تفاصيل العنوان...", Icons.map, maxLines: 4),
              const SizedBox(height: 25),
              const Text("🕒 اختر فترة العمل", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 15),
              _buildShiftToggle(),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildStep3Terms() {
    String dayName = "";
    if (_selectedDate.isNotEmpty) {
      DateTime date = DateTime.parse(_selectedDate);
      dayName = DateFormat('EEEE', 'ar').format(date);
    }
    String shiftText = _selectedShift == 'morning' ? "الصباحية" : "المسائية";

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(35), border: Border.all(color: Colors.black12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.description, color: Colors.amber),
                  SizedBox(width: 10),
                  Text("بنود وشروط الخدمة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const Divider(height: 30),
              _termItem("👥 تفاصيل الطاقم:", "تم اختيار عدد ($_selectedMaidsCount) عاملات لهذه الزيارة."),
              _termItem("📅 تفاصيل الموعد:", "الزيارة محددة يوم ($dayName) الموافق ($_selectedDate) خلال الفترة ($shiftText) ولمدة (${_packageData?['totalHours']}) ساعات عمل فعلي لكل عاملة."),
              _termItem("📍 المنطقة:", "منطقة التنفيذ المحددة هي ($_selectedRegion)."),
              _termItem("🔒 الخصوصية:", "يُمنع تواجد العاملة في حال عدم وجود سيدة المنزل."),
              _termItem("⚖️ حماية قانونية:", "نضمن لك عاملات بأخلاق عالية وموثوقة من طرفنا بعد التعامل الطويل. كما نلتزم بتقديم كافة الدعم والمساعدة للجهات المختصة في حال نشوب أي نزاع قانوني لضمان حقك وحق العاملة."),
              _termItem("🧺 سياسة غسيل الملابس:", "حفاظاً على سلامة العاملة وضماناً للجودة، يتم غسيل الملابس عن طريق الغسالة فقط، ويمنع منعاً باتاً الغسيل اليدوي."),
              _termItem("🧼 الأدوات والمعدات:", "نحن نتكفل بتوفير كافة معدات ومواد النظافة اللازمة لإتمام المهمة."),
              _termItem("🏢 الإشراف:", "يتم تسليم واستلام الخدمة بواسطة مشرف ميداني مختص لضمان الجودة."),
              const SizedBox(height: 20),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _hasAcceptedTerms,
                onChanged: (v) => setState(() => _hasAcceptedTerms = v!),
                title: const Text("أوافق على كافة البنود المذكورة أعلاه", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                activeColor: Colors.blue,
                controlAffinity: ListTileControlAffinity.leading,
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _gpsButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        onPressed: _isLocating ? null : _handleAutoLocation,
        icon: _isLocating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_currentPosition != null ? Icons.check_circle : Icons.gps_fixed),
        label: Text(_isLocating ? "جاري التحديد..." : (_currentPosition != null ? "تم التحديد بنجاح" : "تحديد موقعي (GPS)")),
        style: ElevatedButton.styleFrom(backgroundColor: _currentPosition != null ? Colors.green.shade50 : Colors.blue.shade50, foregroundColor: _currentPosition != null ? Colors.green : Colors.blue, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
      ),
    );
  }

  Widget _buildRegionDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(15)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedRegion,
          isExpanded: true,
          hint: const Text("اختر منطقتك", style: TextStyle(fontSize: 13)),
          items: _regions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
          onChanged: (v) => setState(() => _selectedRegion = v),
        ),
      ),
    );
  }

  Widget _buildShiftToggle() {
    return Row(
      children: [
        Expanded(child: _shiftBtn("☀️ صباحية", "morning")),
        const SizedBox(width: 10),
        Expanded(child: _shiftBtn("🌙 مسائية", "evening")),
      ],
    );
  }

  Widget _shiftBtn(String label, String value) {
    bool isSel = _selectedShift == value;
    return InkWell(
      onTap: () => setState(() => _selectedShift = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: isSel ? Colors.orange.shade50 : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: isSel ? Colors.orange : Colors.black12)),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isSel ? Colors.orange : Colors.grey)),
      ),
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: () async {
        DateTime? picked = await showDatePicker(
          context: context, 
          initialDate: DateTime.now().add(const Duration(days: 1)), 
          firstDate: DateTime.now(), 
          lastDate: DateTime.now().add(const Duration(days: 30)),
          selectableDayPredicate: (DateTime day) => day.weekday != DateTime.friday,
        );
        if (picked != null) {
          String dateStr = picked.toString().split(' ')[0];
          setState(() => _selectedDate = dateStr);
          _checkAvailability(dateStr);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _isDayFull ? Colors.red.shade50 : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: _isDayFull ? Colors.red : Colors.black12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_selectedDate.isEmpty ? "اختر تاريخ الزيارة" : _selectedDate, style: TextStyle(color: _isDayFull ? Colors.red : Colors.black, fontWeight: FontWeight.bold)),
            Icon(Icons.calendar_month, color: _isDayFull ? Colors.red : Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topLeft: Radius.circular(45), topRight: Radius.circular(45))),
      child: Row(
        children: [
          if (_currentStep > 1) IconButton(onPressed: () => setState(() => _currentStep--), icon: const Icon(Icons.arrow_back_ios)),
          Expanded(
            child: SizedBox(
              height: 65,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _handleNext,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : Text(_currentStep < 3 ? "استمرار ➡️" : "تأكيد العرض 🚀", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleNext() {
    if (_currentStep == 1) {
      if (_nameController.text.isEmpty || _selectedDate.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ يرجى إكمال البيانات واختيار التاريخ")));
        return;
      }
      setState(() => _currentStep = 2);
    } else if (_currentStep == 2) {
      if (_selectedRegion == null || _addressController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ يرجى تحديد المنطقة وكتابة العنوان")));
        return;
      }
      if (_currentPosition == null) {
        _handleAutoLocation();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("📍 يرجى السماح بالوصول للموقع (GPS)")));
        return;
      }
      setState(() => _currentStep = 3);
    } else {
      if (!_hasAcceptedTerms) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ يرجى الموافقة على البنود أولاً")));
        return;
      }
      _handleSubmit();
    }
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, {bool isPhone = false, int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      textAlign: isPhone ? TextAlign.left : TextAlign.right,
      decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, color: Colors.blue), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.black12))),
    );
  }

  Widget _buildGenderToggle() {
    return Row(
      children: [
        Expanded(child: _genderBtn("👩 أنثى", "female")),
        const SizedBox(width: 10),
        Expanded(child: _genderBtn("👨 ذكر", "male")),
      ],
    );
  }

  Widget _genderBtn(String label, String value) {
    bool isSelected = _selectedGender == value;
    return InkWell(
      onTap: () => setState(() => _selectedGender = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: isSelected ? Colors.blue.shade50 : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: isSelected ? Colors.blue : Colors.black12)),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.blue : Colors.grey)),
      ),
    );
  }

  Widget _termItem(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue)),
          const SizedBox(height: 4),
          Text(content, style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.4)),
        ],
      ),
    );
  }
}
