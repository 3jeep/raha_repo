import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart'; // إضافة مكتبة جلب العناوين النصية من الإحداثيات
import 'dart:async';
import 'package:intl/intl.dart'; 
import 'dart:ui' as ui; 

// استيراد خدمة الإشعارات الخاصة بمشروعك
import 'notification_service.dart';
import 'fcm_sender.dart'; 

class SingleVisitPage extends StatefulWidget {
  const SingleVisitPage({super.key});

  @override
  State<SingleVisitPage> createState() => _SingleVisitPageState();
}

class _SingleVisitPageState extends State<SingleVisitPage> {
  int _currentStep = 1;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isLocating = false;
  bool _isDayFull = false;
  bool _hasAcceptedTerms = false; 
  int _locationAttemptCount = 0; 

  // المتحكمات والبيانات
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  
  String _selectedGender = "female";
  String _selectedShift = "morning"; 
  int _selectedMaidsCount = 1; 
  String _selectedDate = "";
  double _basePrice = 0; 
  String _singleHours = "5"; 
  Position? _currentPosition;

  // متغيرات المنطقة
  String? _selectedRegion;
  final List<String> _regions = ["أم درمان", "بحري", "شرق النيل", "الخرطوم"];

  int _totalMaidsInSystem = 0;
  List<String> _adminFullDays = [];

  @override
  void initState() {
    super.initState();
    _initDataAndLocation(); // دمج العمليتين عند البدء
  }

  // دالة مجمعة لجلب البيانات والموقع معاً عند الدخول
  Future<void> _initDataAndLocation() async {
    await _fetchInitialData();
    await _handleAutoLocation(); // طلب الإذن وجلب الموقع تلقائياً
  }

  Future<void> _fetchInitialData() async {
    try {
      final settingsSnap = await FirebaseFirestore.instance.collection('settings').doc('cleaning_prices').get();
      final maidsSnap = await FirebaseFirestore.instance.collection('maids').get();
      
      FirebaseFirestore.instance.collection('settings').doc('availability').snapshots().listen((snap) {
        if (snap.exists && mounted) {
          setState(() => _adminFullDays = List<String>.from(snap.data()?['fullDays'] ?? []));
        }
      });

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

      if (mounted) {
        setState(() {
          _basePrice = double.tryParse(settingsSnap.data()?['single_price']?.toString() ?? "0") ?? 0;
          _singleHours = settingsSnap.data()?['single_hours']?.toString() ?? "5";
          _totalMaidsInSystem = maidsSnap.size;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching initial data: $e");
    }
  }

  // دالة التعامل التلقائي مع الموقع (طلب الإذن + الجلب) معدلة تماشياً مع geocoding 3.0.0
  Future<void> _handleAutoLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    setState(() => _isLocating = true);

    try {
      // 1. التأكد من تفعيل خدمة الموقع في الجهاز
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _isLocating = false);
        return;
      }

      // 2. التحقق من الأذونات وطلبها إذا لم تكن موجودة
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _isLocating = false);
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isLocating = false);
        return;
      }

      // 3. جلب الموقع في حال الموافقة
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      
      String areaName = "";
      try {
        // ضبط لغة جلب البيانات جلوبال قبل الاستدعاء تماشياً مع تحديث الحزمة الجديد
        await setLocaleIdentifier("ar");
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude, 
          position.longitude,
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
          _currentPosition = position;
          
          // وضع الحي المجلوب في حقل تفاصيل العنوان وإضافة الإحداثيات
          if (areaName.isNotEmpty) {
            _addressController.text = areaName;
          } else {
            _addressController.text = _addressController.text.replaceAll(RegExp(r'📍 الموقع محدد عبر GPS.*'), '');
          }
          _addressController.text += "\n📍 الموقع محدد عبر GPS (${position.latitude}, ${position.longitude})";
          _isLocating = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLocating = false);
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

    if (mounted) {
      setState(() => _isDayFull = (bookedMaids + _selectedMaidsCount) > _totalMaidsInSystem);
    }
  }

  Future<void> _handleSubmit() async {
    if (_isDayFull) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ اليوم المختار مكتمل")));
      return;
    }
    
    setState(() => _isSubmitting = true);
    final user = FirebaseAuth.instance.currentUser;
    
    double originalPrice = _basePrice * _selectedMaidsCount;
    double discount = 0;
    if (_selectedMaidsCount == 2) discount = 0.05;
    if (_selectedMaidsCount == 3) discount = 0.10;
    double finalPrice = originalPrice * (1 - discount);

    try {
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
        'userId': user!.uid,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'totalHours': _singleHours,
        'packageName': "زيارة مفردة - $_singleHours ساعات ($_selectedMaidsCount عاملة)",
        'serviceType': 'single_visit',
        'paymentStatus': 'pending',
        'discountApplied': "${(discount * 100).toInt()}%",
      });

      NotificationService.showNotification(
        "تم استلام طلبك بنجاح 📥",
        "تاريخ الزيارة: $_selectedDate. عدد العاملات: $_selectedMaidsCount. سيتم التواصل معك هاتفياً."
      );

      final adminSnaps = await FirebaseFirestore.instance
          .collection('users')
          .where('adminType', isEqualTo: 'super')
          .get();

      for (var doc in adminSnaps.docs) {
        String? adminToken = doc.data()['fcmToken'];
        if (adminToken != null && adminToken.isNotEmpty) {
          await FcmSender.sendNotification(
            adminToken,
            "طلب زيارة جديد (عدد $_selectedMaidsCount) 🆕",
            "العميل: ${_nameController.text}\nالتاريخ: $_selectedDate"
          );
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🚀 تم حجز موعدك بنجاح!")));
      }
    } catch (e) {
      if (mounted) setState(() => _isSubmitting = false);
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

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 1: return _buildStep1();
      case 2: return _buildStep2();
      case 3: return _buildStep3Terms();
      default: return _buildStep1();
    }
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
          const Text("طلب زيارة مفردة ✨", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          Text("خدمة الـ $_singleHours ساعات", style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildProgressLine(true),
              const SizedBox(width: 10),
              _buildProgressLine(_currentStep >= 2),
              const SizedBox(width: 10),
              _buildProgressLine(_currentStep == 3),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildProgressLine(bool active) {
    return Expanded(child: Container(height: 4, decoration: BoxDecoration(color: active ? Colors.blue : Colors.white12, borderRadius: BorderRadius.circular(10))));
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
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: _isLocating ? null : _handleAutoLocation,
                  icon: _isLocating 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : Icon(_currentPosition != null ? Icons.check_circle : Icons.gps_fixed),
                  label: Text(_isLocating ? "جاري التحديد..." : (_currentPosition != null ? "تم تحديد الموقع بنجاح" : "تحديد موقعي الجغرافي (GPS)")),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _currentPosition != null ? Colors.green.shade50 : Colors.blue.shade50, 
                    foregroundColor: _currentPosition != null ? Colors.green : Colors.blue, 
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text("المنطقة", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 10),
              _buildRegionDropdown(),
              const SizedBox(height: 20),
              const Text("تفاصيل العنوان", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 10),
              TextField(
                controller: _addressController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: "وصف دقيق للعنوان...",
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                ),
              ),
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

  Widget _buildRegionDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(15),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedRegion,
          isExpanded: true,
          hint: const Text("اختر منطقتك", style: TextStyle(color: Colors.grey, fontSize: 13)),
          icon: const Icon(Icons.location_on_outlined, color: Colors.blue, size: 20),
          items: _regions.map((String region) {
            return DropdownMenuItem<String>(
              value: region,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(region, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            );
          }).toList(),
          onChanged: (String? newValue) {
            setState(() {
              _selectedRegion = newValue;
            });
          },
        ),
      ),
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
              _termItem("📅 تفاصيل الموعد:", "الزيارة محددة يوم ($dayName) الموافق ($_selectedDate) خلال الفترة ($shiftText) ولمدة ($_singleHours) ساعات عمل فعلي لكل عاملة."),
              _termItem("📍 المنطقة:", "منطقة التنفيذ المحددة هي ($_selectedRegion)."),
              _termItem("🔒 الخصوصية:", "يُمنع تواجد العاملة في حال عدم وجود سيدة المنزل."),
              _termItem("⚖️ حماية قانونية:", "نضمن لك عاملات بأخلاق عالية وموثوقة من طرفنا بعد التعامل الطويل. كما نلتزم بتقديم كافة الدعم والمساعدة للجهات المختصة في حال نشوب أي نزاع قانوني لضمان حقك وحق العاملة."),
              _termItem("🧺 سياسة غسيل الملابس:", "حفاظاً على سلامة العاملة وضماناً للجودة، يتم غسيل الملابس عن طريق الغسالة فقط، ويمنع منعاً باتاً الغسيل اليدوي."),
              _termItem("🧼 الأدوات والمعدات:", "نحن نتكفل بتوفير كافة معدات ومواد النظافة اللازمة لإتمام المهمة."),
              _termItem("🏢 الإشراف:", "يتم تسليم واستلام الخدمة بواسطة مشرف ميداني مشرف مختص لضمان الجودة."),
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

  Widget _buildPriceCard() {
    double originalPrice = _basePrice * _selectedMaidsCount;
    double discount = 0;
    String discountLabel = "";

    if (_selectedMaidsCount == 2) {
      discount = 0.05;
      discountLabel = "خصم 5% للعاملة الثانية";
    } else if (_selectedMaidsCount == 3) {
      discount = 0.10;
      discountLabel = "خصم 10% للعاملة الثالثة";
    }

    double finalPrice = originalPrice * (1 - discount);

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(35), border: Border.all(color: Colors.black12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("تكلفة الخدمة الإجمالية", style: TextStyle(color: Colors.grey, fontSize: 10)),
              if (discount > 0) ...[
                 Row(
                   children: [
                     Text("${originalPrice.toStringAsFixed(0)}", style: const TextStyle(fontSize: 14, color: Colors.red, decoration: TextDecoration.lineThrough)),
                     const SizedBox(width: 8),
                     Text(discountLabel, style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                   ],
                 ),
              ],
              Text("${finalPrice.toStringAsFixed(0)} ج.س", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
          const Icon(Icons.flash_on, color: Colors.amber),
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
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.blue : Colors.black12),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.blue : Colors.grey)),
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
    bool isSelected = _selectedShift == value;
    return InkWell(
      onTap: () => setState(() => _selectedShift = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.orange : Colors.black12),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.orange : Colors.grey)),
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
          selectableDayPredicate: (DateTime day) {
            return day.weekday != DateTime.friday;
          },
        );
        if (picked != null) {
          String dateStr = picked.toString().split(' ')[0];
          setState(() => _selectedDate = dateStr);
          _checkAvailability(dateStr);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _isDayFull ? Colors.red.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _isDayFull ? Colors.red : Colors.black12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_selectedDate.isEmpty ? "اختر تاريخ الزيارة" : _selectedDate, 
                 style: TextStyle(color: _isDayFull ? Colors.red : Colors.black, fontWeight: FontWeight.bold)),
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
          if (_currentStep > 1)
            IconButton(onPressed: () => setState(() => _currentStep--), icon: const Icon(Icons.arrow_back_ios)),
          Expanded(
            child: SizedBox(
              height: 65,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _handleNext,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                child: _isSubmitting 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : Text(_currentStep < 3 ? "استمرار ➡️" : "تأكيد الحجز النهائي 🚀", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ يرجى إكمال الاسم واختيار التاريخ")));
        return;
      }
      setState(() => _currentStep = 2);
    } else if (_currentStep == 2) {
      if (_selectedRegion == null || _addressController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ يرجى تحديد المنطقة وكتابة العنوان")));
        return;
      }

      // التحقق من نظام الـ GPS
      if (_currentPosition == null) {
        _handleAutoLocation(); // محاولة الجلب مرة أخرى للمساعدة
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("📍 يرجى تفعيل الـ GPS والسماح بالوصول للموقع لإتمام الحجز بدقة"),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
      
      setState(() => _currentStep = 3);
    } else if (_currentStep == 3) {
      if (!_hasAcceptedTerms) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ يرجى الموافقة على البنود أولاً")));
        return;
      }
      _handleSubmit();
    }
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, {bool isPhone = false}) {
    return TextField(
      controller: controller,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      textAlign: isPhone ? TextAlign.left : TextAlign.right,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.blue, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.black12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.black12)),
      ),
    );
  }
}
