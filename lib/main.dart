import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'async_value.dart';

// PHONE MODEL
class Phone {
  final String id;
  final String brand;
  final String model;
  final double price;

  Phone({
    required this.id,
    required this.brand,
    required this.model,
    required this.price,
  });

  factory Phone.fromJson(String id, Map<String, dynamic> json) {
    return Phone(
      id: id,
      brand: json['brand'] ?? '',
      model: json['model'] ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'brand': brand,
      'model': model,
      'price': price,
    };
  }

  @override
  bool operator ==(Object other) => other is Phone && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// REPOSITORY
abstract class PhoneRepository {
  Future<Phone> addPhone(Phone phone);
  Future<Phone> updatePhone(Phone phone); 
  Future<List<Phone>> getPhones();
  Future<void> deletePhone(String id);
}

class FirebasePhoneRepository implements PhoneRepository {
  static const String baseUrl = 'https://g1-is-the-g1-default-rtdb.asia-southeast1.firebasedatabase.app';
  static const String phonesCollection = "phones";
  static const String allPhonesUrl = '$baseUrl/$phonesCollection.json';

  @override
  Future<Phone> addPhone(Phone phone) async {
    Uri uri = Uri.parse(allPhonesUrl);
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(phone.toJson()),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw Exception('Failed to add phone: ${response.body}');
    }

    final newId = json.decode(response.body)['name'];
    return Phone(id: newId, brand: phone.brand, model: phone.model, price: phone.price);
  }

  @override
  Future<Phone> updatePhone(Phone phone) async {
    Uri uri = Uri.parse('$baseUrl/$phonesCollection/${phone.id}.json');
    final response = await http.patch(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(phone.toJson()),
    );

    if (response.statusCode != HttpStatus.ok) {
      throw Exception('Failed to update phone: ${response.body}');
    }

    return phone;
  }

  @override
  Future<List<Phone>> getPhones() async {
    Uri uri = Uri.parse(allPhonesUrl);
    final response = await http.get(uri);

    if (response.statusCode != HttpStatus.ok) {
      throw Exception('Failed to load phones: ${response.statusCode}');
    }

    final data = json.decode(response.body);
    if (data == null || data is! Map<String, dynamic>) return [];

    return data.entries
        .map((entry) => Phone.fromJson(entry.key, entry.value))
        .toList();
  }

  @override
  Future<void> deletePhone(String id) async {
    Uri uri = Uri.parse('$baseUrl/$phonesCollection/$id.json');
    final response = await http.delete(uri);

    if (response.statusCode != HttpStatus.ok) {
      throw Exception('Failed to delete phone');
    }
  }
}

// PROVIDER
class PhoneProvider extends ChangeNotifier {
  final PhoneRepository _repository;
  AsyncValue<List<Phone>> phonesState = AsyncValue.loading();

  PhoneProvider(this._repository) {
    fetchPhones();
  }

  bool get isLoading => phonesState.state == AsyncValueState.loading;
  bool get hasError => phonesState.state == AsyncValueState.error;
  List<Phone> get phones => phonesState.data ?? [];

  Future<void> fetchPhones() async {
    try {
      phonesState = AsyncValue.loading();
      notifyListeners();
      
      final phones = await _repository.getPhones();
      phonesState = AsyncValue.success(phones);
    } catch (error) {
      phonesState = AsyncValue.error(error);
    }
    notifyListeners();
  }

  Future<void> addPhone(Phone phone) async {
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final tempPhone = Phone(id: tempId, brand: phone.brand, model: phone.model, price: phone.price);
    
    phonesState = AsyncValue.success([...phones, tempPhone]);
    notifyListeners();

    try {
      final addedPhone = await _repository.addPhone(phone);
      phonesState = AsyncValue.success([
        for (final p in phones) p.id == tempId ? addedPhone : p
      ]);
    } catch (error) {
      phonesState = AsyncValue.success([...phones.where((p) => p.id != tempId)]);
      phonesState = AsyncValue.error(error);
    }
    notifyListeners();
  }

  Future<void> updatePhone(Phone phone) async {
    final originalPhone = phones.firstWhere((p) => p.id == phone.id);
    phonesState = AsyncValue.success([
      for (final p in phones) p.id == phone.id ? phone : p
    ]);
    notifyListeners();

    try {
      await _repository.updatePhone(phone);
    } catch (error) {
      phonesState = AsyncValue.success([
        for (final p in phones) p.id == phone.id ? originalPhone : p
      ]);
      phonesState = AsyncValue.error(error);
    }
    notifyListeners();
  }

  Future<void> removePhone(String id) async {
    final currentPhones = [...phones];
    phonesState = AsyncValue.success([...phones.where((p) => p.id != id)]);
    notifyListeners();

    try {
      await _repository.deletePhone(id);
    } catch (error) {
      phonesState = AsyncValue.success(currentPhones);
      phonesState = AsyncValue.error(error);
    }
    notifyListeners();
  }
}

// FORM DIALOG
class PhoneFormDialog extends StatefulWidget {
  final Phone? phone;
  final bool isEditMode;
  const PhoneFormDialog({super.key, this.phone}) : isEditMode = phone != null;

  @override
  State<PhoneFormDialog> createState() => _PhoneFormDialogState();
}

class _PhoneFormDialogState extends State<PhoneFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _brandController;
  late TextEditingController _modelController;
  late TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _brandController = TextEditingController(text: widget.phone?.brand ?? '');
    _modelController = TextEditingController(text: widget.phone?.model ?? '');
    _priceController = TextEditingController(text: widget.phone?.price.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEditMode ? 'Edit Phone' : 'Add Phone'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _brandController,
              decoration: InputDecoration(labelText: 'Brand'),
              validator: (value) => value!.isEmpty ? 'Required' : null,
            ),
            TextFormField(
              controller: _modelController,
              decoration: InputDecoration(labelText: 'Model'),
              validator: (value) => value!.isEmpty ? 'Required' : null,
            ),
            TextFormField(
              controller: _priceController,
              decoration: InputDecoration(labelText: 'Price'),
              keyboardType: TextInputType.number,
              validator: (value) => value!.isEmpty || double.tryParse(value) == null ? 'Invalid price' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, Phone(
                id: widget.phone?.id ?? '',
                brand: _brandController.text,
                model: _modelController.text,
                price: double.parse(_priceController.text),
              ));
            }
          },
          child: Text('Save'),
        ),
      ],
    );
  }
}

// APP
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PhoneProvider>(
      builder: (context, phoneProvider, child) {
        Widget content;

        if (phoneProvider.isLoading) {
          content = Center(child: CircularProgressIndicator());
        } else if (phoneProvider.hasError) {
          content = Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Error: ${phoneProvider.phonesState.error}'),
                ElevatedButton(
                  onPressed: phoneProvider.fetchPhones,
                  child: Text('Retry'),
                ),
              ],
            ),
          );
        } else {
          final phones = phoneProvider.phones;
          content = phones.isEmpty
              ? Center(child: Text("No phones yet"))
              : ListView.builder(
                  itemCount: phones.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text('${phones[index].brand} ${phones[index].model}'),
                    subtitle: Text('\$${phones[index].price}'),
                    trailing: IconButton(
                      icon: Icon(Icons.delete, color: Colors.red),
                      onPressed: () => phoneProvider.removePhone(phones[index].id),
                    ),
                    onTap: () => showDialog(
                      context: context,
                      builder: (context) => PhoneFormDialog(phone: phones[index]),
                    ).then((result) {
                      if (result != null && result is Phone) {
                        phoneProvider.updatePhone(result);
                      }
                    }),
                  ),
                );
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.blue,
            title: Text('Phone Store'),
            actions: [
              IconButton(
                onPressed: phoneProvider.fetchPhones,
                icon: Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
              IconButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (context) => PhoneFormDialog(),
                ).then((result) {
                  if (result != null && result is Phone) {
                    phoneProvider.addPhone(result);
                  }
                }),
                icon: Icon(Icons.add),
                tooltip: 'Add Phone',
              ),
            ],
          ),
          body: content,
        );
      },
    );
  }
}

void main() async {
  final PhoneRepository phoneRepository = FirebasePhoneRepository();
  runApp(
    ChangeNotifierProvider(
      create: (context) => PhoneProvider(phoneRepository),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: const App(),
      ),
    ),
  );
}