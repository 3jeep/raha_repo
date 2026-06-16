import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart'; 
import 'package:firebase_storage/firebase_storage.dart'; 
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'app_constants.dart';

class ManageHandymanPage extends StatefulWidget {
  const ManageHandymanPage({super.key});

  @override
  State<ManageHandymanPage> createState() => _ManageHandymanPageState();
}

class _ManageHandymanPageState extends State<ManageHandymanPage> {
  final user = FirebaseAuth.instance.currentUser;
  bool _isUploadingImage = false; 

  String _selectedProfession = AppConstants.professionsList[0];
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  double? _lat, _lng;
  String? _editingId;
  
  String? _profilePhotoUrl; 

  @override
  void initState() {
    super.initState();
    _loadUserPhoto(); 
  }

  void _loadUserPhoto() {
    if (user != null) {
      FirebaseFirestore.instance.collection('users').doc(user!.uid).snapshots().listen((snap) {
        if (snap.exists && mounted) {
          setState(() {
            _profilePhotoUrl = snap.data()?['photoUrl'];
          });
        }
      });
    }
  }

  Future<FirebaseStorage> _getSecondaryStorageInstance() async {
    FirebaseApp storageApp;
    try {
      storageApp = Firebase.app("secondaryStorageApp");
    } catch (e) {
      storageApp = await Firebase.initializeApp(
        name: "secondaryStorageApp",
        options: const FirebaseOptions(
          apiKey: "AIzaSyDlEBzVFhJzFkDI4mWnTSEQbUGOYBoVvbI",
          authDomain: "group-2f790.firebaseapp.com",
          projectId: "group-2f790",
          storageBucket: "group-2f790.firebasestorage.app",
          messagingSenderId: "532610990999",
          appId: "1:532610990999:web:1ad2bf5149c68774e57ad2",
        ),
      );
    }
    return FirebaseStorage.instanceFor(app: storageApp);
  }

  Future<void> _pickAndUploadImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    
    if (image == null) return;

    setState(() => _isUploadingImage = true);

    try {
      FirebaseStorage secondaryStorage = await _getSecondaryStorageInstance();
      Reference ref = secondaryStorage.ref().child('profiles').child('${user!.uid}.jpg');
      
      UploadTask uploadTask = ref.putFile(File(image.path));
      TaskSnapshot snapshot = await uploadTask;
      
      String downloadUrl = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
        'photoUrl': downloadUrl,
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _profilePhotoUrl = downloadUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🚀 تم رفع وتحديث صورتك الشخصية بنجاح!")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("⚠️ خطأ أثناء الرفع: $e")));
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl, 
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: AppBar(
          title: const Text("لوحة تحكم الحرفيين", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, fontFamily: 'Aljazeera')),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.red),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                }
              }, 
            )
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 15),
              _buildVerifyBanner(),
              const SizedBox(height: 20),
              _buildMyServicesList(),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddServiceSheet(),
          backgroundColor: Colors.black,
          label: const Text("إضافة حرفة جديدة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Aljazeera')),
          icon: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    String? finalPhotoUrl = (_profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty) 
        ? _profilePhotoUrl 
        : (user?.photoURL != null && user!.photoURL!.isNotEmpty ? user?.photoURL : null);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.grey.shade100)),
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
        builder: (context, snapshot) {
          String displayedName = "مستخدم راحة";

          if (snapshot.hasData && snapshot.data!.exists) {
            var userData = snapshot.data!.data() as Map<String, dynamic>;
            if (userData['fullName'] != null && userData['fullName'].toString().trim().isNotEmpty) {
              displayedName = userData['fullName'];
            } else if (user?.phoneNumber != null && user!.phoneNumber!.isNotEmpty) {
              displayedName = user!.phoneNumber!;
            }
          }

          return Row(
            children: [
              GestureDetector(
                onTap: _isUploadingImage ? null : _pickAndUploadImage,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircleAvatar(
                      radius: 28, 
                      backgroundColor: const Color(0xFF1E293B),
                      backgroundImage: finalPhotoUrl != null ? NetworkImage(finalPhotoUrl) : null,
                      child: finalPhotoUrl == null && !_isUploadingImage 
                          ? Text(
                              displayedName.isNotEmpty ? displayedName[0].toUpperCase() : "U", 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)
                            ) 
                          : null,
                    ),
                    if (_isUploadingImage)
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.black45,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 12),
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayedName, 
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, fontFamily: 'Aljazeera')
                    ),
                    const SizedBox(height: 4),
                    const Text("اضغط على الصورة لرفع صورة مخصصة مباشرة", style: TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'Aljazeera')),
                  ],
                ),
              )
            ],
          );
        },
      ),
    );
  }

  Widget _buildVerifyBanner() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('whatsapp').doc('contact').snapshots(),
      builder: (context, snapshot) {
        String whatsappNum = "";
        if (snapshot.hasData && snapshot.data!.exists) {
          var data = snapshot.data!.data() as Map<String, dynamic>;
          whatsappNum = data['contact'] ?? data['number'] ?? "";
        }
        
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(20)),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () async {
              if (whatsappNum.isNotEmpty) {
                final Uri url = Uri.parse("https://wa.me/$whatsappNum?text=أريد توثيق حرفتي في تطبيق راحة");
                if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تعذر فتح تطبيق واتساب")));
                  }
                }
              }
            },
            child: const Padding(
              padding: EdgeInsets.all(15),
              child: Row(
                children: [
                  Icon(Icons.verified, color: Colors.blue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "تواصل معنا واتساب لتوثيق حرفتك",
                      style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Aljazeera'),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, size: 14, color: Colors.blue),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMyServicesList() {
    if (user == null) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('handymen').where('uid', isEqualTo: user?.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        var docs = snapshot.data!.docs;
        
        if (docs.isEmpty) return const Center(child: Text("لا توجد حرف مسجلة حالياً", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontFamily: 'Aljazeera')));

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var s = docs[index].data() as Map<String, dynamic>;
            String docId = docs[index].id;
            bool isActive = s['isActive'] ?? true;
            bool isVerified = s['isVerified'] ?? false;
            int calls = s['total_calls'] ?? 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 15),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.grey.shade100)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(s['profession'], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, fontFamily: 'Aljazeera')),
                              if (isVerified) ...[
                                const SizedBox(width: 5),
                                const Icon(Icons.verified, color: Colors.blue, size: 18),
                              ]
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Row(
                            children: [Icon(Icons.star, color: Colors.amber, size: 14), Icon(Icons.star, color: Colors.amber, size: 14), Icon(Icons.star, color: Colors.amber, size: 14), Icon(Icons.star, color: Colors.amber, size: 14), Icon(Icons.star, color: Colors.amber, size: 14)],
                          ),
                          const SizedBox(height: 4),
                          Text("📍 ${s['locationName']}", style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold, fontFamily: 'Aljazeera')),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(onPressed: () => _initEdit(docId, s), icon: const Icon(Icons.edit, color: Colors.blue, size: 20)),
                          IconButton(onPressed: () => _deleteService(docId), icon: const Icon(Icons.delete, color: Colors.red, size: 20)),
                        ],
                      )
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("📞 عدد مرات التواصل: $calls", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, fontFamily: 'Aljazeera')),
                      SizedBox(
                        width: 150,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(isActive ? "متاح" : "مشغول", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: isActive ? Colors.green : Colors.grey, fontFamily: 'Aljazeera')),
                          value: isActive,
                          activeThumbColor: Colors.green,
                          onChanged: (val) => FirebaseFirestore.instance.collection('handymen').doc(docId).update({'isActive': val}),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddServiceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_editingId == null ? "إضافة حرفة جديدة" : "تعديل البيانات", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, fontFamily: 'Aljazeera')),
              const SizedBox(height: 20),
              DropdownButtonFormField(
                initialValue: _selectedProfession,
                items: AppConstants.professionsList.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (val) => setSheetState(() => _selectedProfession = val!),
                decoration: const InputDecoration(labelText: "نوع الحرفة", labelStyle: TextStyle(fontFamily: 'Aljazeera')),
              ),
              TextField(controller: _locationController, decoration: const InputDecoration(labelText: "اسم المنطقة (الحي)", labelStyle: TextStyle(fontFamily: 'Aljazeera'))),
              const SizedBox(height: 15),
              ElevatedButton.icon(
                onPressed: () async {
                  var pos = await Geolocator.getCurrentPosition();
                  setSheetState(() { _lat = pos.latitude; _lng = pos.longitude; });
                },
                icon: Icon(Icons.my_location, color: _lat != null ? Colors.green : Colors.white),
                label: Text(_lat != null ? "تم تحديد الموقع ✅" : "تحديد موقعي على الخريطة", style: const TextStyle(fontFamily: 'Aljazeera')),
                style: ElevatedButton.styleFrom(backgroundColor: _lat != null ? Colors.green.shade50 : Colors.blue, foregroundColor: _lat != null ? Colors.green : Colors.white),
              ),
              TextField(controller: _phoneController, decoration: const InputDecoration(labelText: "رقم الهاتف", labelStyle: TextStyle(fontFamily: 'Aljazeera')), keyboardType: TextInputType.phone),
              TextField(controller: _bioController, decoration: const InputDecoration(labelText: "نبذة عن خبرتك", labelStyle: TextStyle(fontFamily: 'Aljazeera')), maxLines: 2),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _saveService(),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size(double.infinity, 50)),
                child: const Text("حفظ ونشر الحرفة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Aljazeera')),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ تم تحديث الدالة برمجياً لجلب وثيقة المستخدم وجلب الاسم الثلاثي الكامل (fullName) قبل نشر أو تعديل الحرفة
  void _saveService() async {
    if (_lat == null || _locationController.text.isEmpty || user == null) return;

    setState(() => _isUploadingImage = true);

    try {
      // 1. جلب اسم الحرفي الحقيقي الكامل المخزن في الفايرستور أولاً
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
      String finalRealName = "حرفي راحة";

      if (userDoc.exists) {
        var userData = userDoc.data() as Map<String, dynamic>;
        if (userData['fullName'] != null && userData['fullName'].toString().trim().isNotEmpty) {
          finalRealName = userData['fullName'];
        } else if (userData['name'] != null && userData['name'].toString().trim().isNotEmpty) {
          finalRealName = userData['name'];
        }
      }

      String finalPhotoUrl = _profilePhotoUrl ?? user?.photoURL ?? "";

      var data = {
        'uid': user?.uid,
        'name': finalRealName, // ✅ استخدام الاسم الثلاثي الفعلي القادم من مجموعة الـ users
        'profession': _selectedProfession,
        'phone': _phoneController.text,
        'bio': _bioController.text,
        'locationName': _locationController.text,
        'lat': _lat,
        'lng': _lng,
        'photoUrl': finalPhotoUrl, 
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_editingId == null) {
        await FirebaseFirestore.instance.collection('handymen').add({
          ...data,
          'isVerified': false,
          'isActive': true,
          'rating': 5.0,
          'total_calls': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseFirestore.instance.collection('handymen').doc(_editingId).update(data);
      }

      if (mounted) {
        Navigator.pop(context);
        _resetForm();
      }
    } catch (e) {
      debugPrint("Error saving service: $e");
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  void _initEdit(String id, Map<String, dynamic> s) {
    _editingId = id;
    _selectedProfession = s['profession'];
    _phoneController.text = s['phone'];
    _bioController.text = s['bio'] ?? "";
    _locationController.text = s['locationName'] ?? "";
    _lat = s['lat'];
    _lng = s['lng'];
    _showAddServiceSheet();
  }

  void _resetForm() {
    _editingId = null;
    _phoneController.clear();
    _bioController.clear();
    _locationController.clear();
    _lat = null; _lng = null;
  }

  void _deleteService(String id) {
     FirebaseFirestore.instance.collection('handymen').doc(id).delete();
  }
}
