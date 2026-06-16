import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart'; // إضافة مكتبة تحويل الإحداثيات إلى نصوص وعناوين

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isSaving = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  String _selectedGender = "female"; // القيمة الافتراضية للنوع
  String? _selectedRegion; // متغير المنطقة
  final List<String> _regions = ["أم درمان", "بحري", "شرق النيل", "الخرطوم"]; // قائمة المناطق

  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = _auth.currentUser;
    if (user != null) {
      DocumentSnapshot doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        setState(() {
          _nameController.text = data['fullName'] ?? "";
          _phoneController.text = data['phone'] ?? "";
          _addressController.text = data['address'] ?? "";
          _selectedGender = data['gender'] ?? "female"; // جلب النوع
          _selectedRegion = data['region']; // جلب المنطقة
          _latitude = data['latitude'];
          _longitude = data['longitude'];
        });
      }
    }
    setState(() => _isLoading = false);
  }

  // دالة جلب الموقع الحالية بعد التعديل لتتوافق مع geocoding 3.0.0
  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar("يرجى تفعيل الـ GPS في الهاتف");
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    setState(() => _isSaving = true);
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      
      // جلب اسم الحي أو الشارع بناءً على الإحداثيات الحقيقية المجلوبة
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude, 
        position.longitude,
      );

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        
        // التحقق من نجاح عملية الوصول لبيانات العنوان النصي وتحليله
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          
          // دمج اسم الحي أو الشارع الفرعي في متغير نصي واحد لملء العنوان
          String areaName = place.subLocality ?? ""; 
          if (areaName.isEmpty) {
            areaName = place.thoroughfare ?? ""; // احتياطي في حال عدم توفر subLocality
          }
          if (areaName.isEmpty) {
            areaName = place.name ?? ""; 
          }

          if (areaName.isNotEmpty) {
            _addressController.text = areaName;
          }
        }
      });
      _showSnackBar("✅ تم تحديد إحداثيات موقعك بنجاح");
    } catch (e) {
      _showSnackBar("❌ تعذر جلب الموقع");
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'fullName': _nameController.text,
        'phone': _phoneController.text,
        'address': _addressController.text,
        'gender': _selectedGender, // حفظ النوع
        'region': _selectedRegion, // حفظ المنطقة
        'latitude': _latitude,
        'longitude': _longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _showSnackBar("✅ تم حفظ التعديلات بنجاح");
    } catch (e) {
      _showSnackBar("❌ فشل في حفظ البيانات");
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Aljazeera')), 
        backgroundColor: Colors.black,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF1E293B))));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Transform.translate(
                offset: const Offset(0, -50),
                child: Column(
                  children: [
                    _buildLocationActionCard(),
                    const SizedBox(height: 20),
                    _buildFormCard(),
                    const SizedBox(height: 20),
                    _buildLogoutButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final user = _auth.currentUser;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 80, bottom: 100),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(50), bottomRight: Radius.circular(50)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: Colors.white30, shape: BoxShape.circle),
            child: CircleAvatar(
              radius: 45,
              backgroundImage: NetworkImage(user?.photoURL ?? "https://ui-avatars.com/api/?name=${_nameController.text}&background=random&color=fff"),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            _nameController.text.isEmpty ? "مستخدم جديد" : _nameController.text,
            style: const TextStyle(
              color: Colors.white, 
              fontSize: 22, 
              fontWeight: FontWeight.w900, 
              fontStyle: FontStyle.italic,
              fontFamily: 'Aljazeera',
            ),
          ),
          Text(
            user?.email ?? "",
            style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationActionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 20)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "موقع المنزل 📍", 
                  style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.w900, fontSize: 11, fontStyle: FontStyle.italic, fontFamily: 'Aljazeera'),
                ),
                Text(
                  _latitude != null ? "الموقع مسجل الآن ✅" : "اضغط لتحديد موقعك الحالي ⚠️",
                  style: const TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.blue[600],
            borderRadius: BorderRadius.circular(15),
            child: InkWell(
              onTap: _getCurrentLocation,
              borderRadius: BorderRadius.circular(15),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                child: Text(
                  "تحديد الموقع", 
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, fontFamily: 'Aljazeera'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(35),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 20)],
      ),
      child: Column(
        children: [
          _buildInputLabel("الاسم الكامل"),
          _buildTextField(_nameController, Icons.person_outline),
          const SizedBox(height: 20),
          _buildInputLabel("تحديد النوع"),
          _buildGenderToggle(),
          const SizedBox(height: 20),
          _buildInputLabel("المنطقة"),
          _buildRegionDropdown(),
          const SizedBox(height: 20),
          _buildInputLabel("رقم الهاتف"),
          _buildTextField(_phoneController, Icons.phone_android, isPhone: true),
          const SizedBox(height: 20),
          _buildInputLabel("العنوان (وصف إضافي)"),
          _buildTextField(_addressController, Icons.description_outlined, maxLines: 2),
          const SizedBox(height: 30),
          _buildSaveButton(),
        ],
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
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isSelected ? Colors.blue : Colors.transparent),
        ),
        child: Text(
          label, 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? Colors.blue : Colors.grey, fontFamily: 'Aljazeera'),
        ),
      ),
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
          hint: const Text("اختر منطقتك", style: TextStyle(color: Colors.grey, fontSize: 13, fontFamily: 'Aljazeera')),
          icon: const Icon(Icons.location_on_outlined, color: Color(0xFF1E293B), size: 18),
          items: _regions.map((String region) {
            return DropdownMenuItem<String>(
              value: region,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(region, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Aljazeera')),
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

  Widget _buildInputLabel(String label) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8, right: 5),
        child: Text(
          label, 
          style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w900, fontSize: 10, fontFamily: 'Aljazeera'),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, IconData icon, {bool isPhone = false, int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      textAlign: isPhone ? TextAlign.left : TextAlign.right,
      keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF1E293B)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E293B),
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          elevation: 5,
        ),
        child: _isSaving 
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Text(
              "حفظ التغييرات ✨", 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, fontFamily: 'Aljazeera'),
            ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return InkWell(
      onTap: () async {
        final user = _auth.currentUser;
        if (user != null) {
          // حذف التوكن من الفايرستور قبل تسجيل الخروج
          await _firestore.collection('users').doc(user.uid).update({
            'fcmToken': FieldValue.delete(),
          });
        }
        
        await _auth.signOut();
        if (mounted) {
          // التوجيه المباشر لصفحة تسجيل الدخول
          Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.red[100]!),
        ),
        child: const Center(
          child: Text(
            "تسجيل الخروج 🚪", 
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 11, fontFamily: 'Aljazeera'),
          ),
        ),
      ),
    );
  }
}
