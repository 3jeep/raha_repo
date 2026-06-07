import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart'; // إضافة مكتبة جلب العناوين النصية من الإحداثيات
import 'dart:math';
import 'dart:ui' as ui;

// استيراد خدمة الإشعارات
import 'notification_service.dart';

class MultiVisitContractPage extends StatefulWidget {
  const MultiVisitContractPage({super.key});

  @override
  State<MultiVisitContractPage> createState() => _MultiVisitContractPageState();
}

class _MultiVisitContractPageState extends State<MultiVisitContractPage> {
  // --- States ---
  int _step = 1;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _locating = false;
  bool _hasAccepted = false;
  String _contractId = "";

  // السعر والديناميكية
  String _displayPrice = "جاري التحميل...";
  String _oldPrice = ""; // للسعر المشطوب
  bool _isFirstContract = false; // هل هو أول عقد؟
  String _multiHours = "0"; 
  int _visitCount = 12;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  
  String _gender = "";
  String? _selectedRegion; // حقل المنطقة الجديد
  Map<String, double>? _locationCoords;

  DateTime? _startDate; 
  List<String> _additionalDays = []; 

  // قائمة المناطق - أصبحت فارغة ليتم جلبها من الفايربيس
  List<String> _sudanRegions = [];

  @override
  void initState() {
    super.initState();
    _contractId = "RAHA-${Random().nextInt(90000) + 10000}";
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    final user = FirebaseAuth.instance.currentUser;
    try {
      // 1. جلب قائمة المناطق من كولكشن settings
      final settingsSnap = await FirebaseFirestore.instance.collection('settings').doc('region').get();
      if (settingsSnap.exists && settingsSnap.data()?['array'] != null) {
        setState(() {
          _sudanRegions = List<String>.from(settingsSnap.data()?['array']);
        });
      }

      // 2. جلب بيانات المستخدم
      if (user != null) {
        final docSnap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (docSnap.exists) {
          final data = docSnap.data()!;
          _nameController.text = data['fullName'] ?? "";
          _phoneController.text = data['phone'] ?? "";
          _gender = data['gender'] ?? "";
          _addressController.text = data['address'] ?? "";
          
          if (data['region'] != null && _sudanRegions.contains(data['region'])) {
            _selectedRegion = data['region'];
          }
        }

        // تحقق مما إذا كان هذا هو العقد الأول للعميل
        final contractsSnap = await FirebaseFirestore.instance
            .collection('contracts')
            .where('userId', isEqualTo: user.uid)
            .limit(1)
            .get();
        
        _isFirstContract = contractsSnap.docs.isEmpty;
      }

      // 3. جلب الأسعار وحساب الخصم
      final pricingSnap = await FirebaseFirestore.instance.collection('settings').doc('cleaning_prices').get();
      if (pricingSnap.exists) {
        final pData = pricingSnap.data()!;
        String basePriceStr = (pData['multi_price'] ?? '180,000').toString().replaceAll(',', '');
        double basePrice = double.tryParse(basePriceStr) ?? 180000;

        setState(() {
          if (_isFirstContract) {
            double discountedPrice = basePrice * 0.70; // خصم 30%
            _oldPrice = "${basePrice.toStringAsFixed(0)} ج.س";
            _displayPrice = "${discountedPrice.toStringAsFixed(0)} ج.س";
          } else {
            _displayPrice = "${basePrice.toStringAsFixed(0)} ج.س";
            _oldPrice = "";
          }
          _multiHours = (pData['multi_hours'] ?? "5").toString();
          _visitCount = 12; 
        });
      }
    } catch (e) {
      debugPrint("Error fetching data: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGetLocation() async {
    setState(() => _locating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      
      String areaName = "";
      try {
        // ضبط اللغة الافتراضية قبل الاستدعاء لتتوافق مع الإصدار الجديد 3.0.0
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

      setState(() {
        _locationCoords = {'lat': position.latitude, 'lng': position.longitude};
        if (areaName.isNotEmpty) {
          _addressController.text = areaName;
        }
      });
      _msg("📍 تم تحديد إحداثيات موقعك بدقة");
    } catch (e) {
      _msg("❌ فشل تحديد الموقع، يرجى المحاولة يدوياً");
    } finally {
      setState(() => _locating = false);
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
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(24),
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
    switch (_step) {
      case 1: return _step1PersonalData();
      case 2: return _step2LocationData();
      case 3: return _step3Schedule();
      case 4: return _step4Terms();
      default: return Container();
    }
  }

  Widget _step1PersonalData() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(Icons.person_outline, "البيانات الشخصية"),
        const SizedBox(height: 20),
        _inputLabel("الاسم الكامل"),
        _textField(_nameController, "أدخل اسمك الثلاثي"),
        const SizedBox(height: 16),
        _inputLabel("رقم الهاتف"),
        _textField(_phoneController, "0XXXXXXXXX", isPhone: true),
        const SizedBox(height: 16),
        _inputLabel("الجنس"),
        Row(
          children: [
            _genderOption("👩 أنثى", "female", Colors.pink),
            const SizedBox(width: 12),
            _genderOption("👨 ذكر", "male", Colors.blue),
          ],
        ),
      ],
    );
  }

  Widget _step2LocationData() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(Icons.location_on_outlined, "وصف الموقع الجغرافي"),
        const SizedBox(height: 20),
        _locationBtn(),
        if (_locationCoords != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 8),
            child: Text("✅ تم التقاط الإحداثيات بنجاح", style: TextStyle(color: Colors.green.shade700, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        const SizedBox(height: 20),
        _inputLabel("المنطقة"),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _sudanRegions.contains(_selectedRegion) ? _selectedRegion : null,
              hint: const Text("اختر المنطقة"),
              items: _sudanRegions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) => setState(() => _selectedRegion = v),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _inputLabel("وصف العنوان (شارع، منزل، معلم بارز)"),
        _textField(_addressController, "مثال: الحاج يوسف، شارع الـ 105، بالقرب من...", maxLines: 3),
      ],
    );
  }

  Widget _step3Schedule() {
    final allDays = ["السبت", "الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس"];
    final startDayName = _startDate != null ? _getWeekDayName(_startDate!) : "";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(Icons.calendar_month_outlined, "جدول الزيارات"),
        const SizedBox(height: 20),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now().add(const Duration(days: 1)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 30)),
              locale: const Locale('ar', 'SA'),
              selectableDayPredicate: (day) => day.weekday != DateTime.friday,
            );
            if (picked != null) setState(() { _startDate = picked; _additionalDays.clear(); });
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
            child: Row(children: [
              const Icon(Icons.event, color: Colors.blue),
              const SizedBox(width: 12),
              Text(_startDate == null ? "تحديد تاريخ البداية" : "تبدأ في: ${"${_startDate!.year}-${_startDate!.month}-${_startDate!.day}"} ($startDayName)", style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        const SizedBox(height: 25),
        const Text("اختر يومين إضافيين للزيارات الأسبوعية:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 15),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.3),
          itemCount: allDays.length,
          itemBuilder: (c, i) {
            String dayName = allDays[i];
            bool isStartDay = dayName == startDayName;
            bool isSel = _additionalDays.contains(dayName) || isStartDay;
            return InkWell(
              onTap: isStartDay ? null : () {
                setState(() {
                  if (_additionalDays.contains(dayName)) { _additionalDays.remove(dayName); }
                  else if (_additionalDays.length < 2) { _additionalDays.add(dayName); }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isStartDay ? Colors.blue.shade900 : (isSel ? Colors.blue : Colors.white),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: isSel ? Colors.blue : Colors.grey.shade300, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(dayName, style: TextStyle(color: isSel ? Colors.white : Colors.grey, fontWeight: FontWeight.bold)),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _step4Terms() {
    String attendanceDays = _startDate != null ? "${_getWeekDayName(_startDate!)}، ${_additionalDays.join('، ')}" : "";
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.grey.shade200)),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text("رقم العقد: $_contractId", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                  const Icon(Icons.verified, color: Colors.green),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // عرض السعر بعد الخصم
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(15)),
                    child: Column(
                      children: [
                        const Text("قيمة الاشتراك التعاقدي", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isFirstContract && _oldPrice.isNotEmpty)
                              Text(_oldPrice, style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.red, fontSize: 14)),
                            const SizedBox(width: 10),
                            Text(_displayPrice, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue)),
                          ],
                        ),
                        if (_isFirstContract)
                          const Text("✨ خصم 30% لأول تعاقد مع راحة ✨", style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  _contractSection("📜 تفاصيل الجدول الزمني:", "مراجعة مواعيد زياراتك الأسبوعية المحددة.", Colors.blue),
                  _contractItem(Icons.calendar_month, "تاريخ البدء", "${_startDate?.year}-${_startDate?.month}-${_startDate?.day} (${_getWeekDayName(_startDate!)})", Colors.blue),
                  _contractItem(Icons.event_available, "أيام الحضور أسبوعياً", attendanceDays, Colors.blue),
                  const Divider(height: 30),
                  _contractSection("💎 ضمانات الجودة والخدمة:", "بنود تضمن لك التميز وتحفظ حقوق الجميع.", Colors.amber.shade900),
                  _contractItem(Icons.star, "عاملات خبيرات", "نضمن لك عاملات مدربات وخبيرات في فنون الضيافة والنظافة الشاملة.", Colors.amber.shade700),
                  _contractItem(Icons.cleaning_services, "أدوات النظافة", "نحن نتكفل بتوفير كافة معدات ومواد النظافة اللازمة لإتمام المهمة على أكمل وجه.", Colors.blue),
                  _contractItem(Icons.edit_calendar, "مرونة الجدول", "يُسمح للعميل بتغيير يوم من أيام الزيارات المجدولة إلى يوم آخر لمرة واحدة فقط خلال فترة العقد.", Colors.teal),
                  _contractItem(Icons.gavel, "حماية قانونية", "نلتزم بتقديم كافة الدعم والمساعدة للجهات المختصة في حال نشوب أي نزاع قانوني لضمان حقك وحق العاملة.", Colors.redAccent),
                  _contractItem(Icons.health_and_safety, "كرامة العاملة", "يلتزم العميل بتوفير بيئة عمل آمنة ولائقة، ويمنع أي شكل من أشكال الإساءة   عليك الاتصال بالدعم وسيتم تغير العاملة  عند توفر عاملة اخري.", Colors.green),
                  const Divider(height: 30),
                  _contractItem(Icons.history_toggle_off, "١. نظام الساعات", "مدة الزيارة الواحدة هي ($_multiHours) ساعات عمل فعلي.", Colors.blue),
                  _contractItem(Icons.supervisor_account, "٢. نظام الإشراف", "يتم تسليم واستلام الخدمة بواسطة مشرف ميداني مختص.", Colors.blue),
                  _contractItem(Icons.shield_moon, "٣. الخصوصية", "يُمنع تواجد العاملة في حال عدم وجود سيدة المنزل.", Colors.pink),
                ]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _acceptanceCheckbox(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 30),
      decoration: const BoxDecoration(color: Color(0xFF1E293B), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("نظام تعاقد \"راحة\" ✨", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        Row(children: [1, 2, 3, 4].map((s) => Expanded(child: Container(height: 6, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: _step >= s ? Colors.blue : const Color(0xFF334155), borderRadius: BorderRadius.circular(10))))).toList()),
      ]),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(45)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]),
      child: Row(children: [
        if (_step > 1) IconButton(onPressed: () => setState(() => _step--), icon: const Icon(Icons.arrow_back_ios_new), style: IconButton.styleFrom(backgroundColor: Colors.grey.shade100)),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 60,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _handleNext,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
              child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text("استمرار ➡️", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ]),
    );
  }

  void _handleNext() {
    if (_step == 1) {
      if (_nameController.text.isEmpty || _gender.isEmpty) { _msg("⚠️ يرجى إكمال بياناتك"); return; }
      setState(() => _step = 2);
    } else if (_step == 2) {
      if (_selectedRegion == null || _addressController.text.isEmpty) { _msg("⚠️ يرجى تحديد المنطقة والوصف"); return; }
      setState(() => _step = 3);
    } else if (_step == 3) {
      if (_startDate == null || _additionalDays.length < 2) { _msg("⚠️ يرجى إكمال جدول المواعيد"); return; }
      setState(() => _step = 4);
    } else if (_step == 4) {
      if (!_hasAccepted) { _msg("⚠️ يرجى الموافقة على الشروط"); return; }
      _submit();
    }
  }

  void _submit() async {
    setState(() => _isSubmitting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      String? token = await NotificationService.getDeviceToken();
      List<String> finalDays = [_getWeekDayName(_startDate!), ..._additionalDays];

      await FirebaseFirestore.instance.collection('contracts').add({
        'contractId': _contractId,
        'userId': user?.uid,
        'fullName': _nameController.text,
        'phone': _phoneController.text,
        'gender': _gender,
        'region': _selectedRegion,
        'Address': _addressController.text,
        'locationCoords': _locationCoords,
        'startDate': Timestamp.fromDate(_startDate!),
        'selectedDays': finalDays,
        'status': 'pending',
        'type': "monthly_contract",
        'fcmToken': token,
        'finalPrice': _displayPrice, // حفظ السعر النهائي الذي ظهر للمستخدم
        'isFirstContract': _isFirstContract,
        'createdAt': FieldValue.serverTimestamp(),
      });

      NotificationService.showNotification("تم توثيق عقدك بنجاح 📜", "رقم العقد: $_contractId");
      Navigator.pop(context);
    } catch (e) { _msg("❌ حدث خطأ في الحفظ"); }
    finally { setState(() => _isSubmitting = false); }
  }

  Widget _sectionTitle(IconData icon, String title) => Row(children: [Icon(icon, color: Colors.blue), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]);
  Widget _inputLabel(String t) => Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)));
  Widget _textField(TextEditingController c, String h, {bool isPhone = false, int maxLines = 1}) => TextField(controller: c, maxLines: maxLines, keyboardType: isPhone ? TextInputType.phone : TextInputType.text, decoration: InputDecoration(hintText: h, filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade200))));
  Widget _genderOption(String label, String val, Color color) {
    bool isSel = _gender == val;
    return Expanded(child: InkWell(onTap: () => setState(() => _gender = val), child: Container(padding: const EdgeInsets.symmetric(vertical: 15), decoration: BoxDecoration(color: isSel ? color.withOpacity(0.1) : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: isSel ? color : Colors.grey.shade200)), alignment: Alignment.center, child: Text(label, style: TextStyle(color: isSel ? color : Colors.grey, fontWeight: FontWeight.bold)))));
  }
  Widget _locationBtn() => SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _locating ? null : _handleGetLocation, icon: _locating ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.gps_fixed), label: const Text("تحديد موقعي عبر GPS"), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.withOpacity(0.1), foregroundColor: Colors.blue, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)))));
  Widget _contractSection(String t, String c, Color clr) => Container(margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: clr.withOpacity(0.05), borderRadius: BorderRadius.circular(15)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: TextStyle(color: clr, fontWeight: FontWeight.bold)), Text(c, style: TextStyle(color: clr.withOpacity(0.7), fontSize: 11))]));
  Widget _contractItem(IconData i, String t, String c, Color clr) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [Icon(i, color: clr, size: 20), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Text(c, style: const TextStyle(color: Colors.grey, fontSize: 11))]))]));
  Widget _acceptanceCheckbox() => CheckboxListTile(value: _hasAccepted, onChanged: (v) => setState(() => _hasAccepted = v!), activeColor: Colors.blue, title: const Text("أوافق على أن نظام التايمر وإشراف المشرف هما المرجع في تنفيذ هذا العقد.", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)));
  String _getWeekDayName(DateTime date) => ["الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت", "الأحد"][date.weekday - 1];
  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
}
