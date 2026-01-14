import 'dart:convert'; // Logic: Converting data objects to JSON for local persistence.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Logic: S23 Ultra Haptic engine and system interface control.
import 'package:telephony/telephony.dart'; // Logic: Intercepting bank SMS and scanning history.
import 'package:intl/intl.dart'; // Logic: Professional date and currency (₹) formatting.
import 'package:fl_chart/fl_chart.dart'; // Logic: High-performance data visualization for trends.
import 'package:shared_preferences/shared_preferences.dart'; // Logic: Secured local key-value storage.
import 'package:local_auth/local_auth.dart'; // Logic: Biometric (Fingerprint) and S23 PIN fallback security.

/// Logic: Text Extension | Purpose: Title casing for merchant names (e.g. 'UBER' to 'Uber').
extension StringCasingExtension on String {
  String toTitleCase() => split(' ')
      .map((word) => word.isNotEmpty ? word[0].toUpperCase() + word.substring(1).toLowerCase() : "")
      .join(' ');
}

/// Function: onBackgroundMessage | Logic: Required top-level handler for SMS when app is closed.
@pragma('vm:entry-point')
onBackgroundMessage(SmsMessage message) {
  debugPrint("S23 Capture: ${message.body}");
}

void main() {
  // Logic: Ensure the Flutter framework is ready for hardware plugins (SMS/Auth).
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FinancialVaultApp());
}

class FinancialVaultApp extends StatelessWidget {
  const FinancialVaultApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black, // Essence: Optimized for S23 Ultra AMOLED display.
        colorScheme: const ColorScheme.dark(primary: Colors.cyanAccent),
      ),
      home: const AuthScreen(),
    );
  }
}

// --- CUSTOM UI: RUPEE LOADER ---

/// Widget: RupeeLoader | Use Case: Pulsating ₹ symbol used during information loading or sync.
class RupeeLoader extends StatefulWidget {
  const RupeeLoader({super.key});
  @override
  State<RupeeLoader> createState() => _RupeeLoaderState();
}

class _RupeeLoaderState extends State<RupeeLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    // Logic: Constant pulse effect (1.2 seconds duration).
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.8, end: 1.2).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: const Text("₹", style: TextStyle(fontSize: 80, color: Colors.cyanAccent, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.cyanAccent, blurRadius: 25)])),
    );
  }
}

// --- DATA STRUCTURE ---

class Transaction {
  final String id; // Logic: Unique ID (SMS timestamp) to prevent duplicate entries.
  final double amount;
  final String merchant;
  final String category;
  final String method;
  final DateTime date;
  final bool isCredit;

  Transaction({
    required this.id, required this.amount, required this.merchant,
    required this.category, required this.method, required this.date,
    required this.isCredit,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'amount': amount, 'merchant': merchant, 'category': category,
    'method': method, 'date': date.toIso8601String(), 'isCredit': isCredit,
  };

  factory Transaction.fromMap(Map<String, dynamic> map) => Transaction(
    id: map['id'], amount: map['amount'], merchant: map['merchant'], category: map['category'],
    method: map['method'], date: DateTime.parse(map['date']), isCredit: map['isCredit'] ?? false,
  );
}

// --- MAIN SCREENS ---

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final LocalAuthentication auth = LocalAuthentication();
  bool _isLoading = false;

  /// Function: _login | Logic: S23 Fingerprint/Face sensors with Device PIN fallback.
  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      bool didAuth = await auth.authenticate(
        localizedReason: 'Identity verification for Vault access',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
      if (didAuth && mounted) {
        HapticFeedback.heavyImpact(); // Essence: Confirming access with haptics.
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const Dashboard()));
      }
    } catch (e) {
      debugPrint("Auth Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _isLoading ? const RupeeLoader() : IconButton(
          icon: const Icon(Icons.fingerprint, size: 80, color: Colors.cyanAccent),
          onPressed: _login,
        ),
      ),
    );
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final Telephony telephony = Telephony.instance;
  List<Transaction> _vaultItems = [];
  bool _isSyncing = false;
  String _filter = "All";
  bool _isPieView = false; // Logic: Toggles between line trend and category breakdown.

  final List<String> _cats = ["Food", "Shopping", "Bills", "Travel", "Income", "Other"];
  final List<String> _methods = ["UPI", "Credit Card", "Debit Card", "Cash", "Net Banking"];

  @override
  void initState() {
    super.initState();
    _loadFromLocal(); // Logic: Load stored entries first.
    _setupSMS(); // Logic: Register background SMS listener.
  }

  // --- BUSINESS LOGIC: SMS & DATA ---

  void _setupSMS() async {
    bool? permission = await telephony.requestPhoneAndSmsPermissions;
    if (permission == true) {
      telephony.listenIncomingSms(
        onNewMessage: (msg) => _processMessage(msg.body ?? "", msg.date.toString()),
        listenInBackground: true,
        onBackgroundMessage: onBackgroundMessage,
      );
    }
  }

  Future<void> _syncHistory() async {
    setState(() => _isSyncing = true);
    HapticFeedback.mediumImpact();
    List<SmsMessage> messages = await telephony.getInboxSms(columns: [SmsColumn.BODY, SmsColumn.DATE]);
    for (var msg in messages) {
      _processMessage(msg.body ?? "", msg.date.toString(), silent: true);
    }
    await _saveToLocal();
    setState(() => _isSyncing = false);
  }

  void _processMessage(String body, String uid, {bool silent = false}) {
    // Logic: Regex identifies ₹ symbol and captures the amount.
    final RegExp reg = RegExp(r"(?:Rs|INR|₹)\.?\s?([0-9,]+(?:\.[0-9]{2})?)");
    final match = reg.firstMatch(body);

    if (match != null) {
      double amt = double.parse(match.group(1)!.replaceAll(',', ''));
      bool isCr = body.toLowerCase().contains("credited") || body.toLowerCase().contains("received");
      
      // Logic: DEDUPLICATION check.
      if (!_vaultItems.any((e) => e.id == uid)) {
        _addTransaction(amt, "Bank Alert", isCr ? "Income" : "Other", "Bank", isCr, manualId: uid, silent: silent);
      }
    }
  }

  // --- PERSISTENCE ---

  Future<void> _saveToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('s23_final_vault_v5', jsonEncode(_vaultItems.map((e) => e.toMap()).toList()));
  }

  Future<void> _loadFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    String? raw = prefs.getString('s23_final_vault_v5');
    if (raw != null) {
      setState(() {
        _vaultItems = (jsonDecode(raw) as List).map((e) => Transaction.fromMap(e)).toList();
      });
    }
  }

  void _addTransaction(double a, String m, String c, String meth, bool cr, {String? manualId, bool silent = false}) {
    final t = Transaction(
      id: manualId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      amount: a, merchant: m.toTitleCase(), category: c.toTitleCase(),
      method: meth, date: DateTime.now(), isCredit: cr,
    );
    setState(() => _vaultItems.insert(0, t));
    if (!silent) {
      _saveToLocal();
      HapticFeedback.lightImpact();
    }
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    List<Transaction> filtered = _vaultItems.where((e) {
      if (_filter == "Credit") return e.isCredit;
      if (_filter == "Debit") return !e.isCredit;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("PRIVATE VAULT", style: TextStyle(fontSize: 14, letterSpacing: 3)),
        actions: [
          IconButton(icon: Icon(_isPieView ? Icons.analytics : Icons.pie_chart), onPressed: () => setState(() => _isPieView = !_isPieView)),
          IconButton(icon: const Icon(Icons.sync_rounded), onPressed: _syncHistory),
        ],
      ),
      body: _isSyncing ? const Center(child: RupeeLoader()) : Column(
        children: [
          _isPieView ? _buildPie() : _buildTrendLine(),
          _buildFilterRow(),
          Expanded(child: _buildListView(filtered)),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _showManualSheet, child: const Icon(Icons.add_circle)),
    );
  }

  Widget _buildTrendLine() {
    return Container(
      height: 180, padding: const EdgeInsets.all(20),
      child: LineChart(LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: _vaultItems.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.amount)).toList().reversed.toList(),
            isCurved: true, color: Colors.cyanAccent, barWidth: 2, dotData: const FlDotData(show: false),
          ),
        ],
      )),
    );
  }

  Widget _buildPie() {
    Map<String, double> map = {};
    for (var e in _vaultItems) { map[e.category] = (map[e.category] ?? 0) + e.amount; }
    return SizedBox(height: 180, child: PieChart(PieChartData(
      sections: map.entries.map((ent) => PieChartSectionData(
        value: ent.value, title: ent.key, radius: 45, color: Colors.cyanAccent.withOpacity(0.5),
        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
      )).toList(),
    )));
  }

  Widget _buildFilterRow() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: ["All", "Debit", "Credit"].map((f) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(label: Text(f), selected: _filter == f, onSelected: (s) => setState(() => _filter = f)),
    )).toList());
  }

  Widget _buildListView(List<Transaction> data) {
    return ListView.builder(itemCount: data.length, itemBuilder: (context, i) {
      final t = data[i];
      return ListTile(
        leading: Icon(Icons.payment, color: t.isCredit ? Colors.greenAccent : Colors.white54),
        title: Text(t.merchant),
        subtitle: Text("${t.category} • ${t.method} • ${DateFormat('d MMM').format(t.date)}"),
        trailing: Text("₹${t.amount}", style: TextStyle(fontWeight: FontWeight.bold, color: t.isCredit ? Colors.greenAccent : Colors.white)),
        onLongPress: () => setState(() { _vaultItems.removeAt(i); _saveToLocal(); }),
      );
    });
  }

  void _showManualSheet() {
    double a = 0; String m = ""; String c = _cats[0]; String meth = _methods[0];
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(decoration: const InputDecoration(labelText: "Amount (₹)"), keyboardType: TextInputType.number, onChanged: (v) => a = double.tryParse(v) ?? 0),
        TextField(decoration: const InputDecoration(labelText: "Merchant Name"), onChanged: (v) => m = v),
        DropdownButtonFormField(value: c, items: _cats.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(), onChanged: (v) => c = v as String, decoration: const InputDecoration(labelText: "Category")),
        DropdownButtonFormField(value: meth, items: _methods.map((me) => DropdownMenuItem(value: me, child: Text(me))).toList(), onChanged: (v) => meth = v as String, decoration: const InputDecoration(labelText: "Payment Method")),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: () { _addTransaction(a, m, c, meth, c == "Income"); Navigator.pop(context); }, child: const Text("Commit to Vault")),
        const SizedBox(height: 20),
      ]),
    ));
  }
}