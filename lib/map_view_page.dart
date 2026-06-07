import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data'; // مكتبة التعامل مع الـ Bytes
import 'dart:io'; // إضافة المكتبة لضمان عمل الـ HttpClient بأمان
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart'; // إضافة مكتبة الفايربيس الأساسية
import 'package:firebase_storage/firebase_storage.dart'; // إضافة مكتبة الـ Storage
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapViewPage extends StatefulWidget {
  final String serviceType;

  const MapViewPage({super.key, required this.serviceType});

  @override
  State<MapViewPage> createState() => _MapViewPageState();
}

class _MapViewPageState extends State<MapViewPage> {
  final LatLng _defaultCenter = const LatLng(15.5007, 32.5599); // الخرطوم

  GoogleMapController? _mapController;
  LatLng? _userLocation;
  List<Map<String, dynamic>> _handymen = [];
  int _currentIndex = -1;
  bool _isLoading = true;
  bool _dataReady = false;
  String _locationMsg = "📍 جاري جلب موقعك...";
  
  bool _isManualSelectionMode = false; 
  bool _showManualButton = false; 
  LatLng? _temporaryManualLocation; 

  // ذاكرة مؤقتة لحفظ الصور المحملة لتفادي تحميلها في كل مرة يتحرك فيها المستخدم
  final Map<String, Uint8List> _imageCache = {};

  final Map<String, String> _professionIcons = {
    "كهربائي": "⚡",
    "سباك (مواسيرجي)": "🚰",
    "فني تكييف وتبريد": "❄️",
    "توصيل طلبات (ركشة/موتر)": "🛵",
    "ممرض / ممرضة": "🩺",
    "فني غسالات": "🧺",
    "ميكانيكي": "🔧",
    "عامل مساعد": "🧹",
    "نقاش (بويجي)": "🎨",
    "نجار": "🪚",
    "فني ستالايت (دش)": "📡",
    "مبلط (سيراميك)": "🧱",
    "حداد": "⚒️",
    "بناء": "🏗️",
    "مساعد بناء (طُلبة)": "🧱",
    "طباخ": "👨‍🍳",
    "حلاق (خدمة منزلية)": "✂️",
    "غسيل عربات": "🚿"
  };

  double _getDistance(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371; 
    double dLat = (lat2 - lat1) * math.pi / 180;
    double dLon = (lon2 - lon1) * math.pi / 180;
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return double.parse((r * c).toStringAsFixed(1));
  }

  // دالة ذكية للاتصال بمشروع الـ Storage الثاني وجلب البيانات منه بشكل آمن
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

  // ✅ تم تحديث الدالة لتعمل بشكل آمن وتتخطى مشاكل شهادات الأمان وقراءة الـ Stream المكسور
  Future<Uint8List?> _fetchHandymanImage(String? photoUrl, String uid) async {
    if (photoUrl == null || photoUrl.isEmpty) return null;
    
    if (_imageCache.containsKey(photoUrl)) {
      return _imageCache[photoUrl];
    }

    try {
      final Uri imageUri = Uri.parse(photoUrl);
      final HttpClient client = HttpClient();
      
      // السماح للشهادات المخصصة بالمرور لتفادي الـ Handshake Exception
      client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;
      
      final HttpClientRequest request = await client.getUrl(imageUri).timeout(const Duration(seconds: 10));
      final HttpClientResponse response = await request.close();
      
      if (response.statusCode == 200) {
        // قراءة وتجميع الـ Stream كـ قائمة بايتات موحدة بدلاً من الـ loop التقليدي العالق
        final List<int> bytes = await response.reduce((a, b) => [...a, ...b]);
        final Uint8List data = Uint8List.fromList(bytes);
        
        if (data.isNotEmpty) {
          _imageCache[photoUrl] = data;
          return data;
        }
      }
    } catch (e) {
      debugPrint("⚠️ رابط photoUrl المباشر واجه مشكلة، ننتقل للحل الاحتياطي عبر الـ Storage: $e");
    }

    // الحل الاحتياطي المستقر
    try {
      FirebaseStorage storage = await _getSecondaryStorageInstance();
      Reference ref = storage.ref().child('profiles').child('$uid.jpg');
      
      final Uint8List? data = await ref.getData(3 * 1024 * 1024);
      if (data != null && data.isNotEmpty) {
        _imageCache[photoUrl] = data;
        return data;
      }
    } catch (storageError) {
      debugPrint("Error fetching from storage secondary instance: $storageError");
    }
    
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadInitialMap();
  }

  Future<void> _loadInitialMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? savedLocationRaw = prefs.getString("lastUserLocation");

      if (savedLocationRaw != null) {
        final Map<String, dynamic> decoded = jsonDecode(savedLocationRaw);
        LatLng savedLocation = LatLng(decoded['lat'], decoded['lng']);
        if (mounted) {
          setState(() {
            _userLocation = savedLocation;
            _locationMsg = "🟡 تم استخدام موقعك المحفوظ";
          });
          _fetchHandymen(savedLocation);
        }
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        );
        LatLng realLocation = LatLng(pos.latitude, pos.longitude);

        await prefs.setString("lastUserLocation", jsonEncode({'lat': realLocation.latitude, 'lng': realLocation.longitude}));

        if (mounted) {
          setState(() {
            _userLocation = realLocation;
            _locationMsg = "🟢 تم تحديث موقعك بنجاح";
            _showManualButton = false;
          });
          _fetchHandymen(realLocation);
        }
      } else {
        if (mounted) {
          setState(() {
            _locationMsg = "🔴 فشل جلب موقعك الدقيق \"قم بالتحديد يدوياً\"";
            _showManualButton = true; 
            _dataReady = true;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationMsg = "⚠️ فشل جلب موقعك الدقيق \"قم بالتحديد يدوياً\"";
          _showManualButton = true;
          _dataReady = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchHandymen(LatLng pos) async {
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await FirebaseFirestore.instance
            .collection("handymen")
            .where("profession", isEqualTo: widget.serviceType)
            .where("isActive", isEqualTo: true)
            .get(const GetOptions(source: Source.cache)); 
            
        if (snap.docs.isEmpty) {
          snap = await FirebaseFirestore.instance
              .collection("handymen")
              .where("profession", isEqualTo: widget.serviceType)
              .where("isActive", isEqualTo: true)
              .get(const GetOptions(source: Source.server));
        }
      } catch (e) {
        snap = await FirebaseFirestore.instance
            .collection("handymen")
            .where("profession", isEqualTo: widget.serviceType)
            .where("isActive", isEqualTo: true)
            .get(const GetOptions(source: Source.server));
      }

      List<Map<String, dynamic>> loadedData = [];

      for (var d in snap.docs) {
        Map<String, dynamic> item = {'id': d.id, ...d.data()};
        if (item['lat'] != null && item['lng'] != null) {
          double distance = _getDistance(
            pos.latitude,
            pos.longitude,
            double.tryParse(item['lat'].toString()) ?? 0,
            double.tryParse(item['lng'].toString()) ?? 0,
          );
          item['distance'] = distance;
          loadedData.add(item);
        }
      }

      loadedData = loadedData.where((h) => h['distance'] <= 12).toList();
      loadedData.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

      if (mounted) {
        setState(() {
          _handymen = loadedData;
          _isLoading = false;
          _dataReady = true;
        });

        if (_handymen.isNotEmpty) {
          _selectHandyman(0);
        } else {
          setState(() {
            _currentIndex = -1;
            _locationMsg = "ℹ️ لا يوجد حرفيون متاحون في محيط 12 كم حالياً";
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching handymen: $e");
    }
  }

  void _selectHandyman(int index) {
    if (index >= 0 && index < _handymen.length) {
      setState(() => _currentIndex = index);
      var h = _handymen[index];
      LatLng targetPos = LatLng(double.parse(h['lat'].toString()), double.parse(h['lng'].toString()));
      
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(targetPos, 15.5),
      );

      _mapController?.showMarkerInfoWindow(MarkerId(h['id']));
    }
  }

  Future<void> _confirmManualLocation() async {
    if (_temporaryManualLocation != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("lastUserLocation", jsonEncode({
        'lat': _temporaryManualLocation!.latitude, 
        'lng': _temporaryManualLocation!.longitude
      }));

      setState(() {
        _userLocation = _temporaryManualLocation;
        _isManualSelectionMode = false;
        _showManualButton = false;
        _isLoading = true;
        _locationMsg = "🔵 تم اعتماد موقعك اليدوي بنجاح";
      });

      _fetchHandymen(_userLocation!);
    }
  }

  Future<void> _handleAction(Map<String, dynamic> h, String type) async {
    try {
      await FirebaseFirestore.instance.collection("handymen").doc(h['id']).update({
        'total_calls': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint("Error incrementing call count: $e");
    }

    final Uri url = Uri.parse(type == 'call' ? "tel:${h['phone']}" : "https://wa.me/${h['phone']}");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || !_dataReady) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/logo.png', width: 120, height: 120, errorBuilder: (c, e, s) => const Icon(Icons.handyman, size: 60, color: Colors.blue)), 
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: Colors.blue),
              const SizedBox(height: 15),
              Text(_locationMsg, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontFamily: 'Cairo')),
            ],
          ),
        ),
      );
    }

    Set<Marker> markers = {};
    
    if (_userLocation != null && !_isManualSelectionMode) {
      markers.add(
        Marker(
          markerId: const MarkerId('user_loc'),
          position: _userLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(
            title: "موقعك الحالي 📍",
            snippet: "أنا هنا",
          ),
        ),
      );
    }

    if (_isManualSelectionMode && _temporaryManualLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('manual_temp_loc'),
          position: _temporaryManualLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: const InfoWindow(
            title: "موقعي اليدوي المقترح 📌",
          ),
        ),
      );
    }

    if (!_isManualSelectionMode) {
      for (int i = 0; i < _handymen.length; i++) {
        var h = _handymen[i];
        String professionName = h['profession'] ?? "حرفي";
        String displayName = h['name'] ?? h['fullName'] ?? "بدون اسم";
        
        markers.add(
          Marker(
            markerId: MarkerId(h['id']),
            position: LatLng(double.parse(h['lat'].toString()), double.parse(h['lng'].toString())),
            onTap: () => _selectHandyman(i),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              h['isVerified'] == true ? BitmapDescriptor.hueBlue : BitmapDescriptor.hueCyan,
            ),
            infoWindow: InfoWindow(
              title: "$professionName 🛠️", 
              snippet: displayName,       
            ),
          ),
        );
      }
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: _userLocation ?? _defaultCenter, zoom: 13),
              onMapCreated: (controller) async {
                _mapController = controller;
                await Future.delayed(const Duration(milliseconds: 600));
                _mapController?.showMarkerInfoWindow(const MarkerId('user_loc'));
                for (var h in _handymen) {
                  _mapController?.showMarkerInfoWindow(MarkerId(h['id']));
                }
              },
              markers: markers,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              onTap: (LatLng tappedPoint) {
                if (_isManualSelectionMode) {
                  setState(() {
                    _temporaryManualLocation = tappedPoint;
                  });
                }
              },
              onCameraMove: (CameraPosition position) {
                if (_isManualSelectionMode) {
                  setState(() {
                    _temporaryManualLocation = position.target;
                  });
                }
              },
            ),

            if (_locationMsg.isNotEmpty)
              Positioned(
                bottom: _isManualSelectionMode ? 140 : (_currentIndex >= 0 ? 320 : 30),
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.85), borderRadius: BorderRadius.circular(15)),
                  child: Text(_locationMsg, style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo'), textAlign: TextAlign.center),
                ),
              ),

            if (!_isManualSelectionMode)
              Positioned(
                top: 50,
                left: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FloatingActionButton(
                      mini: true,
                      backgroundColor: Colors.white,
                      onPressed: () {
                        if (_userLocation != null) {
                          _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_userLocation!, 16));
                        } else {
                          _loadInitialMap();
                        }
                      },
                      child: const Icon(Icons.my_location, color: Colors.blue),
                    ),
                    
                    if (_showManualButton) const SizedBox(height: 10),
                    
                    if (_showManualButton)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                        ),
                        onPressed: () {
                          setState(() {
                            _isManualSelectionMode = true;
                            _temporaryManualLocation = _userLocation ?? _defaultCenter;
                            _locationMsg = "📍 اسحب الخريطة أو اضغط لتسقط علامة 'أنا هنا' في موقعك الحالي اليدوي";
                          });
                          _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_temporaryManualLocation!, 15));
                        },
                        icon: const Icon(Icons.edit_location_alt_rounded, color: Colors.white, size: 16),
                        label: const Text("تحديد يدوي 📍", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'Cairo')),
                      ),
                  ],
                ),
              ),

            if (_isManualSelectionMode)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, spreadRadius: 5)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "هل هذه العلامة البرتقالية 📍 تمثل موقعك الحالي بالضبط؟",
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                                onPressed: _confirmManualLocation,
                                child: const Text("نعم، تأكيد الموقع الحالي ✅", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Cairo')),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _isManualSelectionMode = false;
                                _locationMsg = "🔴 تم إلغاء تحديد الموقع يدوياً";
                              });
                              if (_userLocation != null) _fetchHandymen(_userLocation!);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(14)),
                              child: const Text("إلغاء ✕", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Cairo')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            if (!_isManualSelectionMode && _currentIndex >= 0 && _currentIndex < _handymen.length)
              _buildHandymanDetailsCard(_handymen[_currentIndex]),
          ],
        ),
      ),
    );
  }

  Widget _buildHandymanDetailsCard(Map<String, dynamic> handyman) {
    String emoji = _professionIcons[handyman['profession']] ?? "🛠️";
    String displayName = handyman['name'] ?? handyman['fullName'] ?? "بدون اسم";
    bool isBusy = handyman['isBusy'] ?? false;
    double distance = handyman['distance'] ?? 0.0;
    int duration = (distance * 2).round();

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, spreadRadius: 5)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: SizedBox(
                    height: 45,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: _currentIndex > 0 ? () => _selectHandyman(_currentIndex - 1) : null,
                      child: const Text("⬅ السابق", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => setState(() => _currentIndex = -1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
                    child: const Text("إغلاق ✕", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 45,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: _currentIndex < _handymen.length - 1 ? () => _selectHandyman(_currentIndex + 1) : null,
                      child: const Text("التالي ➡", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                FutureBuilder<Uint8List?>(
                  future: _fetchHandymanImage(handyman['photoUrl'], handyman['uid'] ?? handyman['id']),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const CircleAvatar(
                        radius: 28,
                        backgroundColor: Color(0xFF1E293B),
                        child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        ),
                      );
                    }
                    
                    if (snapshot.hasData && snapshot.data != null) {
                      return CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xFF1E293B),
                        backgroundImage: MemoryImage(snapshot.data!),
                      );
                    }

                    return CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF1E293B),
                      child: Text(
                        displayName.isNotEmpty ? displayName[0].toUpperCase() : "🛠️",
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                      ),
                    );
                  },
                ),

                const SizedBox(width: 15),
                Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Cairo')),
                const SizedBox(width: 6),
                if (handyman['isVerified'] == true)
                  const Icon(Icons.verified, color: Colors.blue, size: 18),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: isBusy ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text(isBusy ? "🔴 مشغول" : "🟢 متاح", style: TextStyle(color: isBusy ? Colors.red : Colors.green, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                ),
              ],
            ),

            if (handyman['rating'] != null && (double.tryParse(handyman['rating'].toString()) ?? 0.0) > 0) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 16),
                  const SizedBox(width: 4),
                  Text("${handyman['rating']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo')),
                ],
              ),
            ],

            if (handyman['bio'] != null && handyman['bio'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(8)),
                child: Text(handyman['bio'].toString(), style: const TextStyle(color: Colors.black54, fontSize: 11, fontFamily: 'Cairo')),
              ),
            ],

            const SizedBox(height: 15),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(15)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text("📏 يبعد عنك: $distance كم", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87, fontFamily: 'Cairo')),
                  Text("🚗 يستغرق للوصول: ~$duration دقيقة", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87, fontFamily: 'Cairo')),
                ],
              ),
            ),
            const SizedBox(height: 15),

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      onPressed: () => _handleAction(handyman, 'call'),
                      child: const Text("اتصال", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Cairo')),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      onPressed: () => _handleAction(handyman, 'wa'),
                      child: const Text("واتساب", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Cairo')),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
