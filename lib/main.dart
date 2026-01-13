import 'dart:convert'; // Use Case: Converting Transaction objects to JSON strings for Auto-Save.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:telephony/telephony.dart'; // Significance: Accesses S23 SMS hardware locally.
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Essence: Offline-only data persistence.

void main() => runApp(const PrivateExpenseApp());

/// Root Widget: Optimized for S23 Ultra's AMOLED display (Deep Blacks).
class PrivateExpenseApp extends StatelessWidget {
  const PrivateExpenseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyanAccent, brightness: Brightness.dark),
      ),
      home: const ExpenseDashboard(),
    );
  }
}

/// Transaction Blueprint: Data structure for individual expense logs.
class Transaction {
  final String id; // Use Case: Unique identifier for stable list deletion.
  final double amount;
  final String merchant;
  final String category;
  final DateTime date;

  Transaction({
    required this.id, 
    required this.amount, 
    required this.merchant, 
    required this.category, 
    required this.date
  });

  // Essence: Serializes the object into a Map for local JSON storage.
  Map<String, dynamic> toJson() => {
    'id': id, 'amount': amount, 'merchant': merchant, 'category': category, 'date': date.toIso8601String(),
  };

  // Essence: Deserializes JSON Map back into a Transaction object.
  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
    id: json['id'] ?? DateTime.now().toString(),
    amount: json['amount'],
    merchant: json['merchant'],
    category: json['category'],
    date: DateTime.parse(json['date']),
  );
}

class ExpenseDashboard extends StatefulWidget {
  const ExpenseDashboard({super.key});
  @override
  State<ExpenseDashboard> createState() => _ExpenseDashboardState();
}

class _ExpenseDashboardState extends State<ExpenseDashboard> {
  // --- CORE STATE VARIABLES ---
  final Telephony telephony = Telephony.instance; // Logic: S23 Local hardware service.
  final List<Transaction> _allTransactions = []; // Significance: The master source of truth for data.
  List<Transaction> _filteredTransactions = []; // Significance: The current view (changes via search).
  final NumberFormat inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹'); // Use Case: INR formatting.
  final List<String> _categories = ['Food', 'Bills', 'Petrol', 'UPI', 'Shopping'];
  final TextEditingController _searchController = TextEditingController(); // Essence: Monitors search input.
  double _monthlyBudget = 50000.0;

  @override
  void initState() {
    super.initState();
    _loadFromDisk(); // Use Case: Restore data on boot.
    _initSMSListener(); // Significance: Start tracking bank SMS alerts.
  }

  // --- LOGIC: AUTO-SAVE & PERSISTENCE ---

  /// Significance: Writes data to the S23 Ultra internal flash storage as JSON.
  Future<void> _saveToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = json.encode(_allTransactions.map((t) => t.toJson()).toList());
    await prefs.setString('s23_offline_vault', encoded);
  }

  /// Significance: Reads the JSON string and populates the UI on startup.
  Future<void> _loadFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('s23_offline_vault');
    if (data != null) {
      final List<dynamic> decoded = json.decode(data);
      setState(() {
        _allTransactions.addAll(decoded.map((m) => Transaction.fromJson(m)).toList());
        _filteredTransactions = _allTransactions; // Sync current view.
      });
    }
  }

  // --- LOGIC: SEARCH & DELETE ---

  /// Significance: Filters the list by Merchant name as the user types.
  void _runSearch(String query) {
    setState(() {
      _filteredTransactions = _allTransactions
          .where((tx) => tx.merchant.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  /// Use Case: Removes a mistake or test transaction.
  /// Logic: Deletes from the master list, syncs view, and updates the S23 disk.
  void _deleteTransaction(String id) {
    setState(() {
      _allTransactions.removeWhere((tx) => tx.id == id);
      _filteredTransactions = List.from(_allTransactions); // Update view.
    });
    _saveToDisk(); // Significance: Ensure deletion is permanent on disk.
    
    // UI Feedback for S23 users
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Transaction deleted"), duration: Duration(seconds: 1)),
    );
  }

  // --- LOGIC: SMS AUTOMATION ---

  /// Essence: Requests S23 permissions and attaches the background listener.
  void _initSMSListener() async {
    bool? permission = await telephony.requestPhoneAndSmsPermissions;
    if (permission == true) {
      telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) => _processSms(message.body ?? ""),
        listenInBackground: true, // App tracks even when screen is locked.
      );
    }
  }

  void _processSms(String body) {
    RegExp reg = RegExp(r"(?:INR|Rs\.?|₹)\s?([0-9,]+(?:\.[0-9]{2})?)");
    var match = reg.firstMatch(body);
    if (match != null) {
      double amt = double.parse(match.group(1)!.replaceAll(',', ''));
      String merch = body.contains("at ") ? body.split("at ")[1].split(" ")[0] : "Bank UPI";
      _showConfirmDialog(amt, merch);
    }
  }

  // --- UI COMPONENTS ---

  /// Significance: Generates a Pie Chart based on category-sum logic.
  Widget _buildPieChart() {
    return SizedBox(
      height: 180,
      child: PieChart(PieChartData(sections: _categories.map((c) {
        double sum = _allTransactions.where((t) => t.category == c).fold(0, (p, t) => p + t.amount);
        return PieChartSectionData(
          value: sum == 0 ? 0.01 : sum,
          title: sum > 0 ? c : "",
          color: Colors.primaries[_categories.indexOf(c) % Colors.primaries.length],
          radius: 40,
        );
      }).toList())),
    );
  }

  /// Logic: Central function to add a record and trigger Auto-Save.
  void _addEntry(double a, String m, String c) {
    setState(() {
      final newTx = Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(), 
        amount: a, merchant: m, category: c, date: DateTime.now()
      );
      _allTransactions.insert(0, newTx);
      _filteredTransactions = _allTransactions;
    });
    _saveToDisk(); // Significance: Permanent offline save.
  }

  @override
  Widget build(BuildContext context) {
    double total = _allTransactions.fold(0, (sum, t) => sum + t.amount);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Private Manager"),
        actions: [IconButton(icon: const Icon(Icons.share), onPressed: _exportCSV)],
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          _buildPieChart(),
          _buildBudgetProgress(total),
          Expanded(child: _buildTransactionList()),
          _buildBottomSearch(), // Search at the bottom for S23 ergonomics.
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _showManualForm, child: const Icon(Icons.add)),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
    );
  }

  // --- LIST WITH SWIPE-TO-DELETE ---

  Widget _buildTransactionList() {
    return ListView.builder(
      itemCount: _filteredTransactions.length,
      itemBuilder: (ctx, i) {
        final tx = _filteredTransactions[i];
        // Significance: Allows the user to "Dismiss" (Delete) items via a swipe gesture.
        return Dismissible(
          key: Key(tx.id),
          direction: DismissDirection.endToStart, // Swipe Left to delete.
          background: Container(
            color: Colors.redAccent,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (dir) => _deleteTransaction(tx.id),
          child: ListTile(
            title: Text(tx.merchant),
            subtitle: Text(tx.category),
            trailing: Text(inr.format(tx.amount), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  // --- OTHER UI WIDGETS ---

  Widget _buildBudgetProgress(double total) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: LinearProgressIndicator(
        value: (total / _monthlyBudget).clamp(0, 1),
        minHeight: 12,
        borderRadius: BorderRadius.circular(10),
        color: total > _monthlyBudget ? Colors.redAccent : Colors.cyanAccent,
      ),
    );
  }

  Widget _buildBottomSearch() {
    return BottomAppBar(
      height: 70,
      child: TextField(
        controller: _searchController,
        onChanged: _runSearch,
        decoration: InputDecoration(
          hintText: "Search merchant...",
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  void _showConfirmDialog(double a, String m) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("SMS Detected"),
      content: Text("Log ₹$a at $m?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("No")),
        ElevatedButton(onPressed: () { _addEntry(a, m, "UPI"); Navigator.pop(ctx); }, child: const Text("Yes")),
      ],
    ));
  }

  void _showManualForm() {
    double a = 0; String m = ""; String? c = _categories[0];
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(decoration: const InputDecoration(labelText: "INR Amount"), keyboardType: TextInputType.number, onChanged: (v) => a = double.tryParse(v) ?? 0),
        TextField(decoration: const InputDecoration(labelText: "Merchant"), onChanged: (v) => m = v),
        DropdownButtonFormField(value: c, items: _categories.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: (v) => c = v as String?),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: () { _addEntry(a, m, c!); Navigator.pop(ctx); }, child: const Text("Save Locally")),
        const SizedBox(height: 20),
      ]),
    ));
  }

  void _exportCSV() async {
    String csv = "Date,Merchant,Category,Amount\n";
    for (var t in _allTransactions) csv += "${t.date},${t.merchant},${t.category},${t.amount}\n";
    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/S23_Expenses.csv");
    await file.writeAsString(csv);
    await Share.shareXFiles([XFile(file.path)], text: 'Financial Export');
  }
}