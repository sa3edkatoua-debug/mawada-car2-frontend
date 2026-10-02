// ignore_for_file: deprecated_member_use, library_private_types_in_public_api, library_prefixes, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

// استيراد مكتبات الـ PDF وإعادة التشغيل
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:restart_app/restart_app.dart';

void main() {
  runApp(const VehicleEntryApp());
}

class VehicleEntryApp extends StatelessWidget {
  const VehicleEntryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نظام إدارة دخول السيارات',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'SA'),
      supportedLocales: const [
        Locale('ar', 'SA'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// نموذج بيانات السيارة
class Vehicle {
  final String id;
  String model;
  String color;
  String plateNumber;
  String ownerName;
  final DateTime entryTime;

  Vehicle({
    required this.id,
    required this.model,
    required this.color,
    required this.plateNumber,
    required this.ownerName,
    required this.entryTime,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'model': model,
        'color': color,
        'plateNumber': plateNumber,
        'ownerName': ownerName,
        'entryTime': entryTime.toIso8601String(),
      };

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        id: json['id'].toString(),
        model: json['model'] ?? '',
        color: json['color'] ?? 'غير محدد',
        plateNumber: json['plateNumber'] ?? '',
        ownerName: json['ownerName'] ?? 'غير محدد',
        entryTime: DateTime.parse(json['entryTime']),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final String domainUrl = 'https://sad-views-look.loca.lt';

  late IO.Socket socket;
  Timer? _fallbackTimer;

  final List<Vehicle> _vehicles = [];
  List<List<dynamic>> _csvData = [];

  final List<String> _modelsList = ['تويوتا كامري', 'هيونداي إلنترا', 'كيا سيراتو', 'نيسان صني'];
  final List<String> _colorsList = ['أبيض', 'أسود', 'فضي', 'أحمر', 'أزرق', 'رمادي'];
  final List<String> _ownersList = ['مكتب 1', 'مكتب 2', 'مكتب 3', 'مكتب 812 '];

  String? _selectedModel;
  String? _selectedColor;
  String? _selectedOwner;

  final _formKey = GlobalKey<FormState>();
  final _customModelController = TextEditingController();
  final _customColorController = TextEditingController();
  final _customOwnerController = TextEditingController();
  final _plateController = TextEditingController();

  bool _isCustomModel = false;
  bool _isCustomColor = false;
  bool _isCustomOwner = false;
  bool _isLoading = false;

  String _sortBy = 'time';

  final Map<String, String> _customHeaders = {
    'Content-Type': 'application/json',
  };

  @override
  void initState() {
    super.initState();
    _fetchDataFromApi();
    _initSocket();

    _fallbackTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _fetchDataFromApi(isBackground: true);
    });
  }

  void _initSocket() {
    socket = IO.io(
      domainUrl,
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .build(),
    );

    socket.onConnect((_) {
      debugPrint('تم الاتصال بالمزامنة اللحظية بنجاح');
    });

    socket.on('vehicles_updated', (_) {
      _fetchDataFromApi(isBackground: true);
    });

    socket.onDisconnect((_) => debugPrint('تم الانفصال عن المزامنة اللحظية'));
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    socket.dispose();
    _customModelController.dispose();
    _customColorController.dispose();
    _customOwnerController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _fetchDataFromApi({bool isBackground = false}) async {
    if (!isBackground) {
      setState(() => _isLoading = true);
    }
    try {
      final vehiclesRes = await http.get(
        Uri.parse('$domainUrl/api/vehicles'),
        headers: _customHeaders,
      );
      final optionsRes = await http.get(
        Uri.parse('$domainUrl/api/options'),
        headers: _customHeaders,
      );

      if (vehiclesRes.statusCode == 200) {
        final List<dynamic> vehiclesJson = jsonDecode(vehiclesRes.body);
        if (mounted) {
          setState(() {
            _vehicles.clear();
            _vehicles.addAll(vehiclesJson.map((e) => Vehicle.fromJson(e)).toList());
            
            for (var v in _vehicles) {
              if (v.ownerName.isNotEmpty && !_ownersList.contains(v.ownerName)) {
                _ownersList.add(v.ownerName);
              }
            }
          });
        }
      }

      if (optionsRes.statusCode == 200) {
        final optionsData = jsonDecode(optionsRes.body);
        if (mounted) {
          setState(() {
            final List<String> apiModels = List<String>.from(optionsData['models'] ?? []);
            final List<String> apiColors = List<String>.from(optionsData['colors'] ?? []);

            for (var m in apiModels) {
              if (!_modelsList.contains(m)) _modelsList.add(m);
            }
            for (var c in apiColors) {
              if (!_colorsList.contains(c)) _colorsList.add(c);
            }
          });
        }
      }
    } catch (e) {
      if (!isBackground) {
        _loadVehiclesLocal();
      }
    } finally {
      if (!isBackground && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadVehiclesLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('vehicles_data');
    if (data != null) {
      final List<dynamic> jsonList = jsonDecode(data);
      if (mounted) {
        setState(() {
          _vehicles.clear();
          _vehicles.addAll(jsonList.map((e) => Vehicle.fromJson(e)).toList());
        });
      }
    }
  }

  // تصدير وتحميل التقرير اليومي كملف PDF وإعادة تشغيل التطبيق تلقائياً
  Future<void> _downloadDailyReportPDFAndRestart() async {
    if (_vehicles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد سيارات مسجلة حالياً لتصدير التقرير'), backgroundColor: Colors.orange),
      );
      return;
    }

    final fontData = await PdfGoogleFonts.amiriRegular();
    final fontBoldData = await PdfGoogleFonts.amiriBold();

    final pdf = pw.Document();
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'التقرير اليومي للسيارات المسجلة ($todayStr)',
                      style: pw.TextStyle(font: fontBoldData, fontSize: 16),
                    ),
                    pw.Text(
                      'Engineer Saeed Katoua',
                      style: pw.TextStyle(font: fontData, fontSize: 10, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'إجمالي عدد السيارات: ${_vehicles.length}',
                style: pw.TextStyle(font: fontData, fontSize: 12),
              ),
              pw.SizedBox(height: 15),
              pw.Table.fromTextArray(
                headers: ['وقت الدخول', 'المالك / المكتب', 'اللون', 'نوع السيارة', 'رقم اللوحة'],
                data: _vehicles.map((v) => [
                  DateFormat('yyyy/MM/dd hh:mm a').format(v.entryTime),
                  v.ownerName,
                  v.color,
                  v.model,
                  v.plateNumber,
                ]).toList(),
                cellStyle: pw.TextStyle(font: fontData, fontSize: 10),
                headerStyle: pw.TextStyle(font: fontBoldData, fontSize: 11),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              ),
            ],
          );
        },
      ),
    );

    final Uint8List bytes = await pdf.save();
    final fileName = 'vehicles_report_$todayStr.pdf';

    if (kIsWeb) {
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final _ = html.AnchorElement(href: url)
        ..setAttribute("download", fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تنزيل التقرير ($fileName) بنجاح! جاري إعادة تشغيل التطبيق...'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));

      if (kIsWeb) {
        html.window.location.reload();
      } else {
        Restart.restartApp();
      }
    }
  }

  void _clearFormFields() {
    _formKey.currentState?.reset();
    _customModelController.clear();
    _customColorController.clear();
    _customOwnerController.clear();
    _plateController.clear();

    setState(() {
      _selectedModel = null;
      _selectedColor = null;
      _selectedOwner = null;
      _isCustomModel = false;
      _isCustomColor = false;
      _isCustomOwner = false;
    });
  }

  Future<void> _addVehicle() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final String finalModel = _isCustomModel 
        ? _customModelController.text.trim() 
        : (_selectedModel ?? '');
    final String finalColor = _isCustomColor 
        ? _customColorController.text.trim() 
        : (_selectedColor ?? '');
    final String finalOwner = _isCustomOwner 
        ? _customOwnerController.text.trim() 
        : (_selectedOwner ?? '');

    if (finalModel.isEmpty || finalColor.isEmpty || finalOwner.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار نوع السيارة، اللون، والمالك بشكل صحيح'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final newVehicle = Vehicle(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      model: finalModel,
      color: finalColor,
      plateNumber: _plateController.text.trim(),
      ownerName: finalOwner,
      entryTime: DateTime.now(),
    );

    try {
      final res = await http.post(
        Uri.parse('$domainUrl/api/vehicles'),
        headers: _customHeaders,
        body: jsonEncode(newVehicle.toJson()),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (mounted) {
          if (!_modelsList.contains(finalModel)) _modelsList.add(finalModel);
          if (!_colorsList.contains(finalColor)) _colorsList.add(finalColor);
          if (!_ownersList.contains(finalOwner)) _ownersList.add(finalOwner);

          _clearFormFields();
          _fetchDataFromApi(isBackground: true);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تسجيل الدخول والحفظ بالسيرفر والمزامنة بنجاح!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('رمز الخطأ: ${res.statusCode}');
      }
    } catch (e) {
      _vehicles.add(newVehicle);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('vehicles_data', jsonEncode(_vehicles.map((v) => v.toJson()).toList()));

      if (mounted) {
        _clearFormFields();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر الاتصال بالسيرفر، تم حفظ البيانات محلياً.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showEditDialog(Vehicle vehicle) {
    final editFormKey = GlobalKey<FormState>();
    final editModelController = TextEditingController(text: vehicle.model);
    final editColorController = TextEditingController(text: vehicle.color);
    final editPlateController = TextEditingController(text: vehicle.plateNumber);
    final editOwnerController = TextEditingController(text: vehicle.ownerName);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit, color: Colors.indigo),
              SizedBox(width: 8),
              Text('تعديل بيانات السيارة'),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: editFormKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: editModelController,
                    decoration: const InputDecoration(labelText: 'نوع السيارة', border: OutlineInputBorder()),
                    validator: (val) => val == null || val.isEmpty ? 'يرجى إدخال النوع' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: editColorController,
                    decoration: const InputDecoration(labelText: 'اللون', border: OutlineInputBorder()),
                    validator: (val) => val == null || val.isEmpty ? 'يرجى إدخال اللون' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: editPlateController,
                    decoration: const InputDecoration(labelText: 'رقم اللوحة', border: OutlineInputBorder()),
                    validator: (val) => val == null || val.isEmpty ? 'يرجى إدخال رقم اللوحة' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: editOwnerController,
                    decoration: const InputDecoration(labelText: 'اسم المالك / المكتب', border: OutlineInputBorder()),
                    validator: (val) => val == null || val.isEmpty ? 'يرجى إدخال اسم المالك' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (editFormKey.currentState!.validate()) {
                  final updatedVehicle = Vehicle(
                    id: vehicle.id,
                    model: editModelController.text.trim(),
                    color: editColorController.text.trim(),
                    plateNumber: editPlateController.text.trim(),
                    ownerName: editOwnerController.text.trim(),
                    entryTime: vehicle.entryTime,
                  );

                  Navigator.pop(context);
                  await _updateVehicleData(updatedVehicle);
                }
              },
              child: const Text('حفظ التعديلات'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateVehicleData(Vehicle updatedVehicle) async {
    try {
      final res = await http.put(
        Uri.parse('$domainUrl/api/vehicles/${updatedVehicle.id}'),
        headers: _customHeaders,
        body: jsonEncode(updatedVehicle.toJson()),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 201) {
        _updateLocalVehicleList(updatedVehicle);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث البيانات بالسيرفر بنجاح!'), backgroundColor: Colors.green),
        );
      } else {
        throw Exception();
      }
    } catch (_) {
      _updateLocalVehicleList(updatedVehicle);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث البيانات محلياً (تعذر الاتصال بالسيرفر)'), backgroundColor: Colors.orange),
      );
    }
  }

  void _updateLocalVehicleList(Vehicle updatedVehicle) async {
    setState(() {
      int index = _vehicles.indexWhere((v) => v.id == updatedVehicle.id);
      if (index != -1) {
        _vehicles[index] = updatedVehicle;
      }
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vehicles_data', jsonEncode(_vehicles.map((v) => v.toJson()).toList()));
  }

  Future<void> _pickAndParseCSV() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      List<List<dynamic>> fields = [];
      if (kIsWeb) {
        final bytes = result.files.single.bytes;
        if (bytes != null) {
          final content = utf8.decode(bytes);
          fields = const CsvToListConverter().convert(content);
        }
      }

      setState(() {
        _csvData = fields;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحميل الملف بنجاح! يحتوي على ${_csvData.length} سجل.'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  void _searchByPlateNumber() {
    final searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.search, color: Colors.indigo),
              SizedBox(width: 8),
              Text('بحث برقم اللوحة'),
            ],
          ),
          content: TextField(
            controller: searchController,
            decoration: const InputDecoration(
              labelText: 'أدخل رقم اللوحة كاملًا',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.directions_car),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final query = searchController.text.trim();
                Navigator.pop(context);
                if (query.isNotEmpty) {
                  _showSearchResult(query);
                }
              },
              child: const Text('بحث'),
            ),
          ],
        );
      },
    );
  }

  void _showSearchResult(String query) {
    final localMatches = _vehicles
        .where((v) => v.plateNumber.toLowerCase().contains(query.toLowerCase()))
        .toList();

    List<List<dynamic>> csvMatches = [];
    if (_csvData.isNotEmpty) {
      csvMatches = _csvData.where((row) {
        return row.any((field) =>
            field.toString().toLowerCase().contains(query.toLowerCase()));
      }).toList();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'نتائج البحث عن: "$query"',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              if (localMatches.isEmpty && csvMatches.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text('لم يتم العثور على أية نتائج مطابقة.'),
                  ),
                ),
              if (localMatches.isNotEmpty) ...[
                const Text('السجلات الحالية بالتطبيق:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                ...localMatches.map((v) => ListTile(
                      leading: const Icon(Icons.directions_car, color: Colors.indigo),
                      title: Text('${v.model} (${v.color}) - ${v.plateNumber}'),
                      subtitle: Text('المالك: ${v.ownerName} | الوقت: ${DateFormat('yyyy/MM/dd HH:mm').format(v.entryTime)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, color: Colors.indigo),
                        onPressed: () {
                          Navigator.pop(context);
                          _showEditDialog(v);
                        },
                      ),
                    )),
              ],
              if (csvMatches.isNotEmpty) ...[
                const Divider(),
                const Text('نتائج الملف المرفوع (CSV):',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                ...csvMatches.map((row) => ListTile(
                      leading: const Icon(Icons.file_present, color: Colors.orange),
                      title: Text(row.join(' - ')),
                    )),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Vehicle> displayedVehicles = List.from(_vehicles);

    if (_sortBy == 'owner') {
      displayedVehicles.sort((a, b) => a.ownerName.compareTo(b.ownerName));
    } else if (_sortBy == 'model') {
      displayedVehicles.sort((a, b) => a.model.compareTo(b.model));
    } else {
      displayedVehicles.sort((a, b) => b.entryTime.compareTo(a.entryTime));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('إدارة دخول السيارات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Engineer Saeed Katoua', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.refresh),
            tooltip: 'تحديث الواجهة',
            onPressed: () => _fetchDataFromApi(isBackground: false),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'تنزيل تقرير PDF وإعادة التشغيل',
            onPressed: _downloadDailyReportPDFAndRestart,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'بحث برقم اللوحة',
            onPressed: _searchByPlateNumber,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'رفع ملف CSV للبحث',
            onPressed: _pickAndParseCSV,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('إجمالي السيارات المسجلة', style: TextStyle(color: Colors.grey)),
                        Text('${_vehicles.length} سيارة',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: _downloadDailyReportPDFAndRestart,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('تنزيل التقرير PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تسجيل دخول سيارة جديدة',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      const SizedBox(height: 15),

                      if (!_isCustomModel) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _selectedModel,
                          decoration: InputDecoration(
                            labelText: '1. اختر نوع السيارة',
                            prefixIcon: const Icon(Icons.directions_car),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add),
                              tooltip: 'كتابة اسم جديد',
                              onPressed: () {
                                setState(() {
                                  _isCustomModel = true;
                                  _selectedModel = null;
                                });
                              },
                            ),
                          ),
                          items: _modelsList.map((model) {
                            return DropdownMenuItem(value: model, child: Text(model));
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedModel = val),
                          validator: (val) => (!_isCustomModel && val == null) ? 'يرجى اختيار نوع السيارة' : null,
                        ),
                      ] else ...[
                        TextFormField(
                          controller: _customModelController,
                          decoration: InputDecoration(
                            labelText: '1. اكتب نوع السيارة الجديد',
                            prefixIcon: const Icon(Icons.edit),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.list),
                              tooltip: 'العودة للقائمة المنسدلة',
                              onPressed: () {
                                setState(() {
                                  _isCustomModel = false;
                                });
                              },
                            ),
                          ),
                          validator: (val) => (_isCustomModel && (val == null || val.isEmpty)) ? 'يرجى كتابة نوع السيارة' : null,
                        ),
                      ],

                      const SizedBox(height: 12),

                      if (!_isCustomColor) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _selectedColor,
                          decoration: InputDecoration(
                            labelText: '2. اختر لون السيارة',
                            prefixIcon: const Icon(Icons.palette),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add),
                              tooltip: 'كتابة لون جديد',
                              onPressed: () {
                                setState(() {
                                  _isCustomColor = true;
                                  _selectedColor = null;
                                });
                              },
                            ),
                          ),
                          items: _colorsList.map((color) {
                            return DropdownMenuItem(value: color, child: Text(color));
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedColor = val),
                          validator: (val) => (!_isCustomColor && val == null) ? 'يرجى اختيار اللون' : null,
                        ),
                      ] else ...[
                        TextFormField(
                          controller: _customColorController,
                          decoration: InputDecoration(
                            labelText: '2. اكتب لون السيارة الجديد',
                            prefixIcon: const Icon(Icons.edit),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.list),
                              tooltip: 'العودة للقائمة المنسدلة',
                              onPressed: () {
                                setState(() {
                                  _isCustomColor = false;
                                });
                              },
                            ),
                          ),
                          validator: (val) => (_isCustomColor && (val == null || val.isEmpty)) ? 'يرجى كتابة اللون' : null,
                        ),
                      ],

                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _plateController,
                        decoration: const InputDecoration(
                          labelText: '3. رقم اللوحة (مثال: أ ب ج 1234)',
                          prefixIcon: Icon(Icons.badge),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.isEmpty ? 'يرجى إدخال رقم اللوحة' : null,
                      ),
                      const SizedBox(height: 12),

                      if (!_isCustomOwner) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _selectedOwner,
                          decoration: InputDecoration(
                            labelText: '4. اختر اسم المالك / المكتب',
                            prefixIcon: const Icon(Icons.person),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add),
                              tooltip: 'كتابة اسم مالك/مكتب جديد',
                              onPressed: () {
                                setState(() {
                                  _isCustomOwner = true;
                                  _selectedOwner = null;
                                });
                              },
                            ),
                          ),
                          items: _ownersList.map((owner) {
                            return DropdownMenuItem(value: owner, child: Text(owner));
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedOwner = val),
                          validator: (val) => (!_isCustomOwner && val == null) ? 'يرجى اختيار اسم المالك أو المكتب' : null,
                        ),
                      ] else ...[
                        TextFormField(
                          controller: _customOwnerController,
                          decoration: InputDecoration(
                            labelText: '4. اكتب اسم المالك / المكتب الجديد',
                            prefixIcon: const Icon(Icons.edit),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.list),
                              tooltip: 'العودة للقائمة المنسدلة',
                              onPressed: () {
                                setState(() {
                                  _isCustomOwner = false;
                                });
                              },
                            ),
                          ),
                          validator: (val) => (_isCustomOwner && (val == null || val.isEmpty)) ? 'يرجى كتابة اسم المالك' : null,
                        ),
                      ],

                      const SizedBox(height: 12),

                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '5. وقت الدخول (تلقائي)',
                          prefixIcon: Icon(Icons.access_time),
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          DateFormat('yyyy/MM/dd - hh:mm a').format(DateTime.now()),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                      ),
                      const SizedBox(height: 15),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _addVehicle,
                          icon: _isLoading 
                              ? const SizedBox(
                                  width: 20, 
                                  height: 20, 
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                                )
                              : const Icon(Icons.add_circle),
                          label: Text(_isLoading ? 'جاري التسجيل...' : 'تسجيل الدخول الآن', style: const TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 25),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'قائمة السيارات المسجلة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
                ),
                Row(
                  children: [
                    const Text('ترتيب حسب: ', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    DropdownButton<String>(
                      value: _sortBy,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'time', child: Text('الأحدث دخولاً')),
                        DropdownMenuItem(value: 'owner', child: Text('اسم المالك')),
                        DropdownMenuItem(value: 'model', child: Text('نوع السيارة')),
                      ],
                      onChanged: (val) => setState(() => _sortBy = val!),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            displayedVehicles.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20.0),
                      child: Text('لا توجد سيارات مسجلة حالياً.'),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: displayedVehicles.length,
                    itemBuilder: (context, index) {
                      final vehicle = displayedVehicles[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.indigo.shade50,
                            child: const Icon(
                              Icons.directions_car,
                              color: Colors.indigo,
                            ),
                          ),
                          title: Text(
                            '${vehicle.model} - ${vehicle.color} (${vehicle.plateNumber})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'المالك: ${vehicle.ownerName}\nوقت الدخول: ${DateFormat('yyyy/MM/dd - hh:mm a').format(vehicle.entryTime)}',
                          ),
                          isThreeLine: true,
                          trailing: ElevatedButton.icon(
                            onPressed: () => _showEditDialog(vehicle),
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('تعديل البيانات'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo.shade50,
                              foregroundColor: Colors.indigo,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
            const SizedBox(height: 30),

            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Text(
                  '© جميع الحقوق محفوظة لـ Engineer Saeed Katoua',
                  style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}