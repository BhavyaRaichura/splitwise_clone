import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'utils/settlement_engine.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data'; // Needed to handle image bytes for the web
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'dart:html' as html; // The native web library!
import 'dart:ui'; // Required for ImageFilter
import 'temp.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // This checks for CI/CD environment variables first, then defaults to your temp.dart
  const String supabaseUrl = String.fromEnvironment('NahiHai', defaultValue: NahiHai);
  const String supabaseKey = String.fromEnvironment('NahiDunga', defaultValue: NahiDunga);

  await Supabase.initialize(
    url: supabaseUrl, 
    anonKey: supabaseKey,
  );

  runApp(const SplitApp());
}

class SplitApp extends StatelessWidget {
  const SplitApp({super.key});

  @override
  Widget build(BuildContext context) {
    // This checks if Supabase currently has a saved session on the phone
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      title: 'Splitwise by Bhavya',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      // THE BOUNCER:
      home: session != null ? const DashboardScreen() : const LoginScreen(),
    );
  }
}

// ---------------------------------------------------------
// DASHBOARD SCREEN (Final: Bottom Nav + Single Net Balance)
// ---------------------------------------------------------
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0; // Tracks which bottom tab is active
  Key _refreshKey = UniqueKey();
  @override
  void initState() {
    super.initState();
  }


  void _showExpenseTargetDialog(String myUserId) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 16.0),
                child: Text('Who are you splitting with?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
              ),
              ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.person, color: Colors.white)),
                title: const Text('Friends', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: const Text('Split with one or multiple friends'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const AdhocSplitScreen())).then((_) => _triggerRefresh());
                },
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.blueGrey, child: Icon(Icons.group, color: Colors.white)),
                title: const Text('Groups', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: const Text('Add an expense to an existing group'),
                onTap: () {
                  Navigator.pop(context);
                  // We can temporarily route them to the Groups tab index, 
                  // or you can implement a quick group selector screen here in the future!
                  setState(() => _currentIndex = 2); 
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _triggerRefresh() {
    setState(() { _refreshKey = UniqueKey(); });
  }

  // --- GLOBAL NET BALANCE MATH ENGINE ---
  Future<List<Map<String, dynamic>>> _fetchGlobalBalances(String myUserId) async {
    final myGroups = await Supabase.instance.client
        .from('group_members')
        .select('group_id')
        .eq('user_id', myUserId);
    
    Map<String, double> netBalancesByPerson = {};
    
    for (var g in myGroups) {
      final settlements = await getFinalSettlements(g['group_id']);
      for (var s in settlements) {
        if (s.fromUser == myUserId) {
          netBalancesByPerson[s.toUser] = (netBalancesByPerson[s.toUser] ?? 0) - s.amount;
        } else if (s.toUser == myUserId) {
          netBalancesByPerson[s.fromUser] = (netBalancesByPerson[s.fromUser] ?? 0) + s.amount;
        }
      }
    }
    
    if (netBalancesByPerson.isEmpty) return [];
    
    Map<String, String> nameMap = {};
    for(String id in netBalancesByPerson.keys) {
       final p = await Supabase.instance.client.from('profiles').select('display_name').eq('id', id).maybeSingle();
       if (p != null) nameMap[id] = p['display_name'] ?? 'Unknown User';
    }
    
    List<Map<String, dynamic>> finalBalances = [];
    netBalancesByPerson.forEach((userId, amount) {
      if (amount.abs() > 0.01) {
        // ---> NEW: INCLUDED userId SO WE CAN ROUTE TO THEIR LEDGER <---
        finalBalances.add({'userId': userId, 'name': nameMap[userId] ?? 'Unknown', 'amount': amount});
      }
    });
    return finalBalances;
  }

  // --- TAB 1: LIQUID GLASS BALANCES BLOCK ---
  Widget _buildBalancesTab(String myUserId) {
    return FutureBuilder(
      key: _refreshKey,
      future: _fetchGlobalBalances(myUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.teal));
        }
        
        final balances = snapshot.data as List<Map<String, dynamic>>? ?? [];
        
        double overallNetBalance = 0;
        for (var b in balances) {
          overallNetBalance += b['amount']; 
        }

        // The beautiful mesh gradient background that makes the glass pop
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F2027), // Deep space black
                Color(0xFF203A43), // Slate blue
                Color(0xFF2C5364), // Dark teal
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // --- HERO GLASS CARD (Total Balance) ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                  child: GlassCard(
                    height: 180,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          overallNetBalance == 0 
                              ? 'You are all settled up!' 
                              : (overallNetBalance > 0 ? 'You are owed overall' : 'You owe overall'),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7), 
                            fontSize: 14, 
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '₹${overallNetBalance.abs().toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 48, 
                            fontWeight: FontWeight.w800,
                            color: overallNetBalance == 0 
                                ? Colors.white 
                                : (overallNetBalance > 0 ? const Color(0xFF69F0AE) : const Color(0xFFFF5252)), 
                            shadows: [
                              Shadow(
                                color: overallNetBalance > 0 ? Colors.greenAccent.withOpacity(0.5) : Colors.redAccent.withOpacity(0.5),
                                blurRadius: 20,
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // --- DYNAMIC LIST OF DEBTS ---
                Expanded(
                  child: balances.isEmpty
                    ? Center(
                        child: GlassCard(
                          height: 120,
                          width: MediaQuery.of(context).size.width * 0.8,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline, color: Colors.white.withOpacity(0.5), size: 40),
                              const SizedBox(height: 8),
                              Text('No outstanding balances.', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        itemCount: balances.length,
                        itemBuilder: (context, index) {
                          final b = balances[index];
                          final isOwedToMe = b['amount'] > 0;
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: GlassCard(
                              height: 90,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              onTap: () {
                                // Smooth routing to their specific ledger
                                Navigator.push(
                                  context,
                                  PageRouteBuilder(
                                    pageBuilder: (context, animation, secondaryAnimation) => UserLedgerScreen(
                                      targetUserId: b['userId'], 
                                      targetUserName: b['name']
                                    ),
                                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                      return FadeTransition(opacity: animation, child: child);
                                    },
                                  )
                                ).then((_) => _triggerRefresh());
                              },
                              child: Row(
                                children: [
                                  // Avatar
                                  Container(
                                    height: 50,
                                    width: 50,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: isOwedToMe 
                                            ? [Colors.tealAccent.withOpacity(0.5), Colors.teal] 
                                            : [Colors.redAccent.withOpacity(0.5), Colors.red],
                                      ),
                                    ),
                                    child: const Icon(Icons.person, color: Colors.white),
                                  ),
                                  const SizedBox(width: 16),
                                  
                                  // Name and Status
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          b['name'], 
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          isOwedToMe ? 'Owes you' : 'You owe',
                                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // Amount
                                  Text(
                                    '₹${b['amount'].abs().toStringAsFixed(0)}', 
                                    style: TextStyle(
                                      color: isOwedToMe ? const Color(0xFF69F0AE) : const Color(0xFFFF5252),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 22,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  // --- STATE FOR ACTIVITY FILTERS ---
  final TextEditingController _activitySearchController = TextEditingController();
  String _searchQuery = "";
  DateTimeRange? _selectedDateRange; // <--- ADD THIS LINE!

  // --- TAB 4: LIQUID GLASS AUDIT TRAIL ---
  Widget _buildActivityFeed(String myUserId) {
    return FutureBuilder(
      key: _refreshKey,
      future: Supabase.instance.client
          .from('user_activity_logs') 
          .select()
          .eq('listener_id', myUserId)
          .order('created_at', ascending: false), 
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) 
          return const Center(child: CircularProgressIndicator(color: Colors.tealAccent));
        
        final List<dynamic> allLogs = snapshot.data as List<dynamic>? ?? [];
        final filteredLogs = allLogs.where((log) {
          bool matchesText = true;
          if (_searchQuery.isNotEmpty) {
            final String description = (log['expense_description'] ?? '').toString().toLowerCase();
            final String actor = (log['actor_name'] ?? '').toString().toLowerCase();
            final String action = (log['action'] ?? '').toString().toLowerCase();
            final String query = _searchQuery.toLowerCase();
            matchesText = description.contains(query) || actor.contains(query) || action.contains(query);
          }
          bool matchesDate = true;
          if (_selectedDateRange != null && log['created_at'] != null) {
            final DateTime logDate = DateTime.parse(log['created_at']);
            final DateTime start = _selectedDateRange!.start;
            final DateTime end = _selectedDateRange!.end.add(const Duration(hours: 23, minutes: 59, seconds: 59));
            matchesDate = logDate.isAfter(start) && logDate.isBefore(end);
          }
          return matchesText && matchesDate;
        }).toList();

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 100), // Push below AppBar
              // --- Glass Search Bar ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GlassCard(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: Colors.white.withOpacity(0.7)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _activitySearchController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Search history...',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (value) => setState(() => _searchQuery = value.trim()),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.date_range, color: _selectedDateRange != null ? Colors.tealAccent : Colors.white70),
                        onPressed: () async {
                           final picked = await showDateRangePicker(
                             context: context,
                             firstDate: DateTime(2020),
                             lastDate: DateTime.now().add(const Duration(days: 365)),
                           );
                           if (picked != null) setState(() => _selectedDateRange = picked);
                        },
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // --- Glass Feed ---
              Expanded(
                child: allLogs.isEmpty 
                  ? Center(child: Text('No activity yet.', style: TextStyle(color: Colors.white.withOpacity(0.5))))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredLogs.length,
                      itemBuilder: (context, index) {
                        final log = filteredLogs[index];
                        String actionText = log['action'] ?? 'unknown';
                        Color badgeColor = actionText == 'created' ? Colors.tealAccent : (actionText == 'deleted' ? Colors.redAccent : Colors.blueAccent);
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassCard(
                            height: 90,
                            padding: const EdgeInsets.all(12),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ExpenseDetailScreen(expenseId: log['expense_id'], groupId: log['group_id'])),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(backgroundColor: badgeColor.withOpacity(0.2), child: Icon(Icons.history, color: badgeColor, size: 20)),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('${log['actor_name']} $actionText', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                      Text(
                                        '"${log['expense_description']}" • ₹${log['expense_amount']}', 
                                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              ),
              const SizedBox(height: 80), // Ensure bottom nav doesn't hide content
            ],
          ),
        );
      },
    );
  }

  // --- TABS 2 & 3: LIQUID GLASS GROUPS & FRIENDS LISTS ---
  Widget _buildList(String myUserId, String typeFilter) {
    return FutureBuilder(
      key: _refreshKey,
      future: Supabase.instance.client
          .from('group_members')
          .select('group_id, groups!inner(name, type, group_members(user_id, profiles(display_name)))')
          .eq('user_id', myUserId)
          .eq('groups.type', typeFilter), 
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.tealAccent));
        }
        
        final list = snapshot.data as List<dynamic>? ?? [];
        
        // Unified mesh gradient to match the Balances Tab
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F2027),
                Color(0xFF203A43),
                Color(0xFF2C5364),
              ],
            ),
          ),
          child: list.isEmpty 
            // --- PREMIUM EMPTY STATE ---
            ? Center(
                child: GlassCard(
                  height: 160,
                  width: MediaQuery.of(context).size.width * 0.8,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        typeFilter == 'friend' ? Icons.person_add_disabled : Icons.group_off, 
                        color: Colors.white.withOpacity(0.5), 
                        size: 48
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No ${typeFilter}s yet', 
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap the + button below to get started.', 
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)
                      ),
                    ],
                  ),
                ),
              )
            // --- GLASS LIST ITEMS ---
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 120), // Extra bottom padding for the FAB
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final data = list[index];
                  final String groupId = data['group_id'];
                  String displayName = data['groups']['name'] ?? 'Unknown';
                  
                  if (typeFilter == 'friend') {
                    final members = data['groups']['group_members'] as List<dynamic>? ?? [];
                    final friendData = members.firstWhere(
                      (m) => m['user_id'] != myUserId, 
                      orElse: () => {'profiles': {'display_name': 'Unknown Friend'}}
                    );
                    displayName = friendData['profiles']?['display_name'] ?? 'Unknown Friend';
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GlassCard(
                      height: 80,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      onTap: () {
                        // Smooth cinematic routing
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => GroupViewScreen(
                              groupName: displayName, 
                              groupId: groupId, 
                              isFriendMode: typeFilter == 'friend'
                            ),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return FadeTransition(opacity: animation, child: child);
                            },
                          )
                        ).then((_) => _triggerRefresh());
                      },
                      child: Row(
                        children: [
                          // Glowing Avatar
                          Container(
                            height: 48,
                            width: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: typeFilter == 'friend' 
                                    ? [Colors.tealAccent.withOpacity(0.5), Colors.teal]
                                    : [Colors.blueAccent.withOpacity(0.5), Colors.blue],
                              ),
                            ),
                            child: Icon(
                              typeFilter == 'friend' ? Icons.person : Icons.group, 
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          
                          // Name
                          Expanded(
                            child: Text(
                              displayName, 
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          
                          // Premium subtle arrow
                          Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white.withOpacity(0.3)),
                        ],
                      ),
                    ),
                  );
                },
              ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String myUserId = Supabase.instance.client.auth.currentUser!.id;
    final List<Widget> childrenTabs = [
      _buildBalancesTab(myUserId),
      _buildList(myUserId, 'friend'),
      _buildList(myUserId, 'group'),
      _buildActivityFeed(myUserId),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F2027), // Deep space base color
      extendBodyBehindAppBar: true, // <--- Lets the gradient flow UNDER the top bar
      extendBody: true,             // <--- Lets the gradient flow UNDER the bottom bar
      
      // --- 1. THE GHOST APP BAR ---
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.black.withOpacity(0.2)),
          ),
        ),
        title: const Text(
          'Splitwise by Bhavya', 
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.2)
        ), 
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()))
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white), 
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
            }
          )
        ],
      ),
      
      body: IndexedStack(
        index: _currentIndex,
        children: childrenTabs,
      ),

      // --- 2. THE GLOWING FAB ---
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _currentIndex == 3 
          ? null 
          : Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.tealAccent.withOpacity(0.4), // The Neon Glow!
                    blurRadius: 20, 
                    spreadRadius: 2
                  )
                ]
              ),
              child: FloatingActionButton(
                onPressed: () {
                  if (_currentIndex == 0) {
                    _showExpenseTargetDialog(myUserId);
                  } else if (_currentIndex == 1) {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AddFriendScreen())).then((_) => _triggerRefresh());
                  } else if (_currentIndex == 2) {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateGroupScreen())).then((_) => _triggerRefresh());
                  }
                },
                backgroundColor: const Color(0xFF1DE9B6), // Neon Teal
                foregroundColor: const Color(0xFF0F2027), // Dark icon for contrast
                elevation: 0,
                child: Icon(_currentIndex == 0 ? Icons.add_card : (_currentIndex == 1 ? Icons.person_add : Icons.group_add)),
              ),
            ),

      // --- 3. THE GLASS BOTTOM NAVIGATION DOCK ---
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1), width: 1)),
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  // Wipe search state when leaving Activity tab
                  if (_currentIndex == 3 && index != 3) {
                    _activitySearchController.clear();
                    _searchQuery = "";
                    _selectedDateRange = null;
                  }
                  _currentIndex = index;
                });
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white.withOpacity(0.05), // Fully translucent
              selectedItemColor: const Color(0xFF1DE9B6), // Neon Teal for active tab
              unselectedItemColor: Colors.white54,
              elevation: 0,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Balances'),
                BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Friends'),
                BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Groups'),
                BottomNavigationBarItem(icon: Icon(Icons.flash_on), label: 'Activity'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// GROUP VIEW SCREEN (Liquid Glass Aesthetic)
// ---------------------------------------------------------
class GroupViewScreen extends StatefulWidget {
  final String groupName;
  final String groupId;
  final bool isFriendMode;

  const GroupViewScreen({
    super.key, 
    required this.groupName, 
    required this.groupId,
    this.isFriendMode = false,
  });

  @override
  State<GroupViewScreen> createState() => _GroupViewScreenState();
}

class _GroupViewScreenState extends State<GroupViewScreen> {
  // --- STRICT GROUP DELETION ENGINE ---
  Future<void> _attemptGroupDeletion() async {
    // 1. Run the math engine to ensure balances are absolutely zero
    final settlements = await getFinalSettlements(widget.groupId);
    
    if (settlements.isNotEmpty) {
      // Balances are NOT zero! Block the deletion.
      if (mounted) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Deletion Blocked', style: TextStyle(color: Colors.red)),
            content: const Text('You cannot delete a ledger that has outstanding balances. Please ensure all debts are settled up before closing this group.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Understood')),
            ],
          ),
        );
      }
      return;
    }

    // 2. Balances are zero. Ask for final confirmation.
    bool confirm = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Permanently?'),
        content: Text('Are you sure you want to completely delete "${widget.groupName}"? This action removes all history and cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    // 3. Execute Deletion
    try {
      await Supabase.instance.client.from('groups').delete().eq('id', widget.groupId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ledger deleted successfully.')));
        Navigator.pop(context); // Kick them back to the dashboard
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<Map<String, dynamic>> _fetchLedgerData() async {
    final expenses = await Supabase.instance.client
        .from('expenses')
        .select()
        .eq('group_id', widget.groupId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    final profiles = await Supabase.instance.client.from('profiles').select('id, display_name');

    final Map<String, String> nameMap = {};
    for (var p in profiles) {
      nameMap[p['id']] = p['display_name'] ?? 'Unknown User';
    }

    return {
      'expenses': expenses,
      'names': nameMap,
    };
  }

  // --- NATIVE WEB CSV EXPORT (Zero Dependencies!) ---
  Future<void> _exportToCSV() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating spreadsheet...')),
    );

    try {
      final data = await _fetchLedgerData();
      final List<dynamic> expenses = data['expenses'];
      final Map<String, String> names = data['names'];

      List<List<dynamic>> csvRows = [];
      
      csvRows.add(["Date", "Description", "Category", "Paid By", "Amount (INR)"]);

      for (var e in expenses) {
        final String rawDate = e['created_at'].toString();
        final String cleanDate = rawDate.length > 10 ? rawDate.substring(0, 10) : rawDate;
        final String payerName = names[e['paid_by']] ?? 'Unknown';
        
        csvRows.add([
          cleanDate,
          e['description'] ?? '',
          e['category'] ?? 'General',
          payerName,
          e['amount']
        ]);
      }

      // --- OUR CUSTOM NATIVE CSV CONVERTER ---
      // This helper safely wraps text in quotes if someone used a comma in their description
      String escapeCsv(dynamic value) {
        String str = value.toString();
        if (str.contains(',') || str.contains('"') || str.contains('\n')) {
          return '"${str.replaceAll('"', '""')}"';
        }
        return str;
      }

      // This merges our rows and columns with commas and line-breaks!
      String csvString = csvRows.map((row) {
        return row.map((cell) => escapeCsv(cell)).join(',');
      }).join('\n');
      // ----------------------------------------

      // The magic that tells the web browser to download the file directly
      final bytes = utf8.encode(csvString);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", "${widget.groupName.replaceAll(' ', '_')}_Ledger.csv")
        ..click(); 
        
      html.Url.revokeObjectUrl(url); 

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download complete!'), backgroundColor: Colors.green),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.groupName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.black.withOpacity(0.2)),
          ),
        ),
        actions: [
          // Hide this button if we are in 1-on-1 mode!
          if (!widget.isFriendMode)
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Add Member',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => AddMemberScreen(groupId: widget.groupId)),
                ).then((_) => setState(() {}));
              },
            ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
            onPressed: _exportToCSV, 
          ),
          IconButton(
            icon: const Icon(Icons.pie_chart),
            tooltip: 'Insights',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => GroupChartsScreen(groupId: widget.groupId)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_balance),
            tooltip: 'View Balances',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => BalancesScreen(groupId: widget.groupId)),
              );
            },
          ),
          // ---> NEW DELETION BUTTON <---
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            tooltip: 'Delete Group',
            onPressed: _attemptGroupDeletion,
          )
        ],
      ),


      
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchLedgerData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final data = snapshot.data!;
          final List<dynamic> expenses = data['expenses'];
          final Map<String, String> names = data['names'];

          if (expenses.isEmpty) {
            return const Center(
              child: Text('No expenses yet. Tap + to add one!', 
                style: TextStyle(color: Colors.grey, fontSize: 16)
              )
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 100), 
            itemCount: expenses.length,
            itemBuilder: (context, index) {
              final expense = expenses[index];
              final String payerName = names[expense['paid_by']] ?? 'Unknown';
              final double amount = (expense['amount'] as num).toDouble();
              
              final String rawDate = expense['created_at'].toString();
              final String cleanDate = rawDate.length > 10 ? rawDate.substring(0, 10) : rawDate;
              
              final bool isPayment = expense['description'] == '💸 Payment / Settle Up';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                elevation: 1,
                child: ListTile(
                  // ---> NEW: UNIVERSAL TAP ROUTING <---
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ExpenseDetailScreen(
                          expenseId: expense['id'],
                          groupId: widget.groupId,
                        )
                      ),
                    ).then((_) => setState(() {})); // Refreshes the ledger when you return!
                  },
                  // ---> END NEW CODE <---
                  leading: CircleAvatar(
                    backgroundColor: isPayment ? Colors.green.shade100 : Colors.teal.shade100,
                    child: Icon(
                      isPayment ? Icons.payment : Icons.receipt_long, 
                      color: isPayment ? Colors.green : Colors.teal
                    ),
                  ),
                  title: Text(
                    expense['description'] ?? 'Expense',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('$payerName paid • $cleanDate'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '₹${amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold, 
                          fontSize: 16,
                          color: isPayment ? Colors.green : Colors.black87,
                        ),
                      ),
                      // THE NEW ACTION MENU
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.grey),
                        onSelected: (value) async {
                          if (value == 'edit') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AddExpenseScreen(
                                  groupId: widget.groupId, 
                                  expenseToEdit: expense, // Pass the data over!
                                )
                              ),
                            ).then((_) => setState(() {}));
                          } else if (value == 'delete') {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Moving to trash...')));

                         // 1. Soft Delete the expense (Adds the timestamp)
                         await Supabase.instance.client.from('expenses')
                             .update({'deleted_at': DateTime.now().toIso8601String()})
                             .eq('id', expense['id']);

                         // 2. Log it in the Audit Trail
                         await Supabase.instance.client.from('activity_logs').insert({
                           'expense_id': expense['id'],
                           'group_id': widget.groupId,
                           'actor_id': Supabase.instance.client.auth.currentUser!.id,
                           'action': 'deleted',
                           'expense_description': expense['description'],
                           'expense_amount': expense['amount'],
                         });

                         setState(() {}); // Refresh screen
                       }
                        },
                        itemBuilder: (context) => [
                          if (!isPayment)
                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                            
                          const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                          
                        ],
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FloatingActionButton.extended(
              heroTag: 'btn1', 
              backgroundColor: Colors.green.shade400,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => RecordPaymentScreen(groupId: widget.groupId)),
                ).then((_) => setState(() {}));
              },
              label: const Text('Settle Up'),
              icon: const Icon(Icons.payment),
            ),
            FloatingActionButton.extended(
              heroTag: 'btn2',
              backgroundColor: Colors.teal,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => AddExpenseScreen(groupId: widget.groupId)),
                ).then((_) => setState(() {})); 
              },
              label: const Text('Add Expense'),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// ADD EXPENSE SCREEN (Now with Co-Payers!)
// ---------------------------------------------------------
class AddExpenseScreen extends StatefulWidget {
  final String groupId; 
  final Map<String, dynamic>? expenseToEdit; 
  
  const AddExpenseScreen({super.key, required this.groupId, this.expenseToEdit});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  
  bool _isLoading = false;
  bool _isLoadingMembers = true;
  
  List<Map<String, dynamic>> _members = [];
  
  // --- NEW PAYER VARIABLES ---
  String _payerType = 'single'; 
  String? _singlePayerId;
  final Map<String, TextEditingController> _payerControllers = {};
  
  String _splitType = 'equal'; 
  String _category = 'General';
  String? _singleDebtorId; 
  final Map<String, TextEditingController> _splitControllers = {};

  @override
  void initState() {
    super.initState();
    _fetchGroupMembers();
    
    if (widget.expenseToEdit != null) {
      _descController.text = widget.expenseToEdit!['description'] ?? '';
      _amountController.text = widget.expenseToEdit!['amount'].toString();
      
      const validCategories = ['General', 'Food', 'Travel', 'Rent', 'Entertainment'];
      String savedCategory = widget.expenseToEdit!['category'] ?? 'General';
      _category = validCategories.contains(savedCategory) ? savedCategory : 'General';
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    _amountController.dispose();
    for (var controller in _splitControllers.values) controller.dispose();
    for (var controller in _payerControllers.values) controller.dispose();
    super.dispose();
  }

  Future<void> _fetchGroupMembers() async {
    try {
      final membersData = await Supabase.instance.client
          .from('group_members')
          .select('user_id, profiles(display_name)')
          .eq('group_id', widget.groupId);

      final List<Map<String, dynamic>> parsedMembers = (membersData as List).map((m) {
        final userId = m['user_id'] as String;
        _splitControllers[userId] = TextEditingController(); 
        _payerControllers[userId] = TextEditingController(); // Initialize payer controllers
        
        return {
          'id': userId,
          'name': m['profiles']?['display_name'] ?? 'User ${userId.substring(0, 4)}',
        };
      }).toList();
      
      setState(() {
        _members = parsedMembers;
        if (parsedMembers.isNotEmpty) _singleDebtorId = parsedMembers.first['id'];
        
        // --- LOAD EXISTING PAYERS IF EDITING ---
        if (widget.expenseToEdit != null) {
          if (widget.expenseToEdit!['payer_amounts'] != null) {
            Map<String, dynamic> pAmts = widget.expenseToEdit!['payer_amounts'];
            if (pAmts.length > 1) {
              _payerType = 'multiple';
              pAmts.forEach((key, value) {
                if (_payerControllers.containsKey(key)) {
                  _payerControllers[key]!.text = value.toString();
                }
              });
            } else {
              _payerType = 'single';
              _singlePayerId = pAmts.keys.first;
            }
          } else {
            _payerType = 'single';
            _singlePayerId = widget.expenseToEdit!['paid_by'];
          }
        } else {
          _payerType = 'single';
          _singlePayerId = Supabase.instance.client.auth.currentUser!.id;
        }

        _isLoadingMembers = false;
      });
    } catch (error) {
      setState(() => _isLoadingMembers = false);
    }
  }

  Future<void> _saveExpenseToCloud() async {
    if (_descController.text.trim().isEmpty || _amountController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter both a description and an amount.'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _isLoading = true);

    try {
      // Silently strip commas so the math parser doesn't crash!
      final double totalAmount = double.parse(_amountController.text.replaceAll(',', ''));
      
      // ---> NEW: STRICT LEDGER VALIDATION <---
      if (totalAmount <= 0) throw Exception('Expense amount must be strictly greater than zero to maintain ledger integrity.');
      if (totalAmount > 1000000) throw Exception('Amount exceeds the maximum allowed limit of ₹10,00,000 per transaction.');
      // ---------------------------------------
      
      if (_members.isEmpty) throw Exception('No members found in this group!');
      
      // ---> NEW: SELF-DEBT PREVENTION <---
      if (_payerType == 'single' && _splitType == 'single') {
        if (_singlePayerId == _singleDebtorId) {
          throw Exception('You cannot owe an expense entirely to yourself!');
        }
      }
      // -----------------------------------

      // --- PHASE 1A: PAYER MATH VALIDATION ---
      Map<String, double> finalPayerAmounts = {};
      
      if (_payerType == 'single') {
        if (_singlePayerId == null) throw Exception('Please select who paid.');
        finalPayerAmounts[_singlePayerId!] = totalAmount;
      } else {
        double sumPayers = 0;
        for (var m in _members) {
          double amt = double.tryParse(_payerControllers[m['id']]!.text) ?? 0;
          if (amt > 0) {
            finalPayerAmounts[m['id']] = amt;
            sumPayers += amt;
          }
        }
        if ((sumPayers - totalAmount).abs() > 0.01) {
          throw Exception('The amounts paid by everyone must perfectly add up to the total (₹$totalAmount)! You entered ₹$sumPayers.');
        }
      }

      // --- PHASE 1B: SPLIT MATH VALIDATION ---
      double totalShares = 0; 
      if (_splitType == 'exact') {
        double sum = 0;
        for (var m in _members) sum += double.tryParse(_splitControllers[m['id']]!.text) ?? 0;
        if ((sum - totalAmount).abs() > 0.01) throw Exception('Exact split amounts must add up to ₹$totalAmount!');
      } else if (_splitType == 'percentage') {
        double sumPct = 0;
        for (var m in _members) sumPct += double.tryParse(_splitControllers[m['id']]!.text) ?? 0;
        if ((sumPct - 100.0).abs() > 0.01) throw Exception('Percentages must add up to exactly 100%!');
      } else if (_splitType == 'shares') {
        for (var m in _members) totalShares += double.tryParse(_splitControllers[m['id']]!.text) ?? 0;
        if (totalShares <= 0) throw Exception('Total shares must be greater than 0!');
      }

      // --- PHASE 2: SAVE OR UPDATE EXPENSE ---
      final String targetExpenseId;
      final String primaryPayerFallback = _payerType == 'single' ? _singlePayerId! : finalPayerAmounts.keys.first;

      if (widget.expenseToEdit == null) {
        final expenseResponse = await Supabase.instance.client
            .from('expenses')
            .insert({
              'group_id': widget.groupId,
              'paid_by': primaryPayerFallback, // Legacy fallback
              'payer_amounts': finalPayerAmounts, // The new JSON array!
              'description': _descController.text,
              'amount': totalAmount,
              'category': _category,
            })
            .select()
            .single(); 
        targetExpenseId = expenseResponse['id'];
      } else {
        targetExpenseId = widget.expenseToEdit!['id'];
        await Supabase.instance.client
            .from('expenses')
            .update({
              'paid_by': primaryPayerFallback, 
              'payer_amounts': finalPayerAmounts, 
              'description': _descController.text,
              'amount': totalAmount,
              'category': _category,
            })
            .eq('id', targetExpenseId);

        await Supabase.instance.client.from('expense_splits').delete().eq('expense_id', targetExpenseId);
      }

      // --- PHASE 3: CALCULATE AND SAVE SPLITS ---
      List<Map<String, dynamic>> splitRows = [];
      if (_splitType == 'equal') {
        final double splitAmount = totalAmount / _members.length;
        splitRows = _members.map((m) => {'expense_id': targetExpenseId, 'user_id': m['id'], 'amount_owed': splitAmount}).toList();
      } else if (_splitType == 'single') {
        splitRows = [{'expense_id': targetExpenseId, 'user_id': _singleDebtorId, 'amount_owed': totalAmount}];
      } else if (_splitType == 'exact') {
        splitRows = _members.map((m) => {'expense_id': targetExpenseId, 'user_id': m['id'], 'amount_owed': double.tryParse(_splitControllers[m['id']]!.text) ?? 0}).toList();
      } else if (_splitType == 'percentage') {
        splitRows = _members.map((m) {
          final double pct = double.tryParse(_splitControllers[m['id']]!.text) ?? 0;
          return {'expense_id': targetExpenseId, 'user_id': m['id'], 'amount_owed': totalAmount * (pct / 100)};
        }).toList();
      } else if (_splitType == 'shares') {
        splitRows = _members.map((m) {
          final double userShares = double.tryParse(_splitControllers[m['id']]!.text) ?? 0;
          return {'expense_id': targetExpenseId, 'user_id': m['id'], 'amount_owed': totalAmount * (userShares / totalShares)};
        }).toList();
      }

      await Supabase.instance.client.from('expense_splits').insert(splitRows);
      // --- LOG THE ACTIVITY ---
      await Supabase.instance.client.from('activity_logs').insert({
        'expense_id': targetExpenseId,
        'group_id': widget.groupId,
        'actor_id': Supabase.instance.client.auth.currentUser!.id,
        'action': widget.expenseToEdit == null ? 'created' : 'updated',
        'expense_description': _descController.text,
        'expense_amount': totalAmount,
      });
      if (mounted) Navigator.pop(context);
      
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.expenseToEdit == null ? 'New Expense' : 'Edit Expense'), backgroundColor: Colors.teal.shade100),
      body: _isLoadingMembers 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView( 
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Total Amount (₹)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                  value: _category,
                  items: const [
                    DropdownMenuItem(value: 'General', child: Text('📝 General')),
                    DropdownMenuItem(value: 'Food', child: Text('🍔 Food & Drink')),
                    DropdownMenuItem(value: 'Travel', child: Text('✈️ Travel')),
                    DropdownMenuItem(value: 'Rent', child: Text('🏠 Rent & Utilities')),
                    DropdownMenuItem(value: 'Entertainment', child: Text('🎬 Entertainment')),
                  ],
                  onChanged: (val) => setState(() => _category = val!),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                
                // --- THE NEW CO-PAY UI ---
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Who Paid?', border: OutlineInputBorder()),
                  value: _payerType,
                  items: const [
                    DropdownMenuItem(value: 'single', child: Text('One Person Paid')),
                    DropdownMenuItem(value: 'multiple', child: Text('Multiple People Paid')),
                  ],
                  onChanged: (val) => setState(() => _payerType = val!),
                ),
                const SizedBox(height: 16),

                if (_payerType == 'single')
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Select Payer', border: OutlineInputBorder()),
                    value: _singlePayerId,
                    items: _members.map<DropdownMenuItem<String>>((m) {
                      return DropdownMenuItem<String>(value: m['id'] as String, child: Text(m['name']));
                    }).toList(),
                    onChanged: (val) => setState(() => _singlePayerId = val),
                  ),

                if (_payerType == 'multiple')
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200)
                    ),
                    child: Column(
                      children: _members.map((m) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Expanded(child: Text(m['name'], style: const TextStyle(fontWeight: FontWeight.bold))),
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: _payerControllers[m['id']],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    filled: true,
                                    fillColor: Colors.white,
                                    prefixText: '₹ ',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  ),
                                ),
                              )
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                // -------------------------

                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'How is it split?', border: OutlineInputBorder()),
                  value: _splitType,
                  items: const [
                    DropdownMenuItem(value: 'equal', child: Text('Split Equally')),
                    DropdownMenuItem(value: 'exact', child: Text('Split by Exact Amounts')),
                    DropdownMenuItem(value: 'percentage', child: Text('Split by Percentages')),
                    DropdownMenuItem(value: 'shares', child: Text('Split by Shares')),
                    DropdownMenuItem(value: 'single', child: Text('100% Owed by one person')),
                  ],
                  onChanged: (val) => setState(() => _splitType = val!),
                ),
                const SizedBox(height: 16),

                if (_splitType == 'single')
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Who owes the full amount?', border: OutlineInputBorder()),
                    value: _singleDebtorId,
                    items: _members.map<DropdownMenuItem<String>>((m) {
                      return DropdownMenuItem<String>(value: m['id'] as String, child: Text(m['name']));
                    }).toList(),
                    onChanged: (val) => setState(() => _singleDebtorId = val),
                  ),

                if (_splitType == 'exact' || _splitType == 'percentage' || _splitType == 'shares')
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal.shade200)
                    ),
                    child: Column(
                      children: _members.map((m) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Expanded(child: Text(m['name'], style: const TextStyle(fontWeight: FontWeight.bold))),
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: _splitControllers[m['id']],
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: Colors.white,
                                    prefixText: _splitType == 'exact' ? '₹ ' : '',
                                    suffixText: _splitType == 'percentage' ? ' %' : (_splitType == 'shares' ? ' shares' : ''),
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  ),
                                ),
                              )
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                const SizedBox(height: 32),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveExpenseToCloud,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                    child: _isLoading 
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white)) 
                        : Text(widget.expenseToEdit == null ? 'Save Expense' : 'Update Expense', style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
// ---------------------------------------------------------
// 1. LOGIN SCREEN (Now purely for signing in)
// ---------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _signIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) return;
    
    setState(() => _isLoading = true);
    
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DashboardScreen()));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              const Icon(Icons.account_balance_wallet, size: 80, color: Colors.teal),
              const SizedBox(height: 32),
              const Text('Welcome to Splitwise by Bhavya', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
              ),
              
              // --- FORGOT PASSWORD BUTTON ---
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ForgotPasswordScreen())),
                  child: const Text('Forgot Password?'),
                ),
              ),
              
              const SizedBox(height: 16),
              if (_isLoading) 
                const Center(child: CircularProgressIndicator())
              else ...[
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _signIn,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                    child: const Text('Sign In', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
                
                // --- NAVIGATE TO NEW SIGN UP SCREEN ---
                OutlinedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SignUpScreen())),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Create an Account'),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// 2. FORGOT PASSWORD SCREEN
// ---------------------------------------------------------
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  Future<void> _resetPassword() async {
    if (_emailController.text.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _emailController.text.trim(),
        redirectTo: 'https://bhavyaraichura.github.io/split-app/', // Triggers the deep link back to your app
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset link sent to your email!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password'), backgroundColor: Colors.teal.shade100),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock_reset, size: 80, color: Colors.teal),
            const SizedBox(height: 24),
            const Text(
              'Enter your email address and we will send you a link to securely reset your password.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email Address', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _resetPassword,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                child: _isLoading 
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white))
                    : const Text('Send Reset Link', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// 3. SECURE SIGN UP SCREEN (Full Onboarding)
// ---------------------------------------------------------
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  // Mandatory Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  // Optional Controllers
  final _phoneController = TextEditingController();
  
  bool _isLoading = false;

  // Image & Avatar State
  final ImagePicker _picker = ImagePicker();
  Uint8List? _selectedImageBytes; // Using bytes is required for Flutter Web image uploads
  String? _selectedImageExtension;
  
  String _avatarStyle = 'adventure';
  final List<String> _avatarStyles = ['adventure', 'bottts', 'pixel-art', 'lorelei'];

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final bytes = await image.readAsBytes();
        
        // ---> NEW: 2MB FILE SIZE LIMITER <---
        if (bytes.lengthInBytes > 2097152) { 
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Image is too large! Please select a photo under 2MB.'), backgroundColor: Colors.red)
            );
          }
          return; // Kills the function before uploading
        }
        // ------------------------------------
        
        setState(() {
          _selectedImageBytes = bytes;
          _selectedImageExtension = image.name.split('.').last;
          _avatarStyle = 'custom'; // Indicates we are using a custom upload
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to pick image')));
    }
  }

  Future<void> _createAccount() async {
    // Validate Mandatory Fields
    if (_nameController.text.isEmpty || _emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all mandatory fields (*)'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Create the Auth Identity
      final authResponse = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        phone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
      );

      if (authResponse.user == null) throw Exception('Failed to create account.');
      final String newUserId = authResponse.user!.id;
      String? customAvatarUrl;

      // 2. Upload Custom Photo to Storage Bucket (if selected)
      if (_avatarStyle == 'custom' && _selectedImageBytes != null) {
        final fileName = '$newUserId.${_selectedImageExtension ?? 'png'}';
        
        await Supabase.instance.client.storage.from('avatars').uploadBinary(
          fileName,
          _selectedImageBytes!,
          fileOptions: const FileOptions(upsert: true),
        );
        
        customAvatarUrl = Supabase.instance.client.storage.from('avatars').getPublicUrl(fileName);
      }

      // 3. Create the Database Profile
      // ---> CHANGED 'insert' to 'upsert' TO PREVENT RACE CONDITIONS <---
      await Supabase.instance.client.from('profiles').upsert({
        'id': newUserId,
        'display_name': _nameController.text.trim(),
        'phone_number': _phoneController.text.trim(),
        'avatar_style': _avatarStyle == 'custom' ? 'custom' : _avatarStyle,
        'avatar_url': customAvatarUrl,
      });

      // 4. Success!
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created! Please sign in.'), backgroundColor: Colors.green),
        );
        Navigator.pop(context); // Send them back to login screen
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String dynamicAvatarPreview = 'https://api.dicebear.com/7.x/$_avatarStyle/png?seed=${_nameController.text.isNotEmpty ? _nameController.text : "Bhavya"}';

    return Scaffold(
      appBar: AppBar(title: const Text('Create Account'), backgroundColor: Colors.teal.shade100),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            
            // --- PROFILE PHOTO SELECTOR ---
            const Text('Profile Photo (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    height: 120, width: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, 
                      color: Colors.teal.shade50,
                      image: _avatarStyle == 'custom' && _selectedImageBytes != null
                          ? DecorationImage(image: MemoryImage(_selectedImageBytes!), fit: BoxFit.cover)
                          : null,
                    ),
                    child: _avatarStyle != 'custom'
                        ? ClipOval(child: Image.network(dynamicAvatarPreview, fit: BoxFit.cover))
                        : null,
                  ),
                  FloatingActionButton.small(
                    onPressed: _pickImageFromGallery,
                    backgroundColor: Colors.teal,
                    child: const Icon(Icons.camera_alt, color: Colors.white),
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Avatar Style Chips (Only show if they haven't uploaded a custom image)
            if (_avatarStyle != 'custom') ...[
              const Center(child: Text('Or pick a generated avatar style:', style: TextStyle(color: Colors.grey, fontSize: 12))),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: _avatarStyles.map((style) {
                  return ChoiceChip(
                    label: Text(style),
                    selected: _avatarStyle == style,
                    selectedColor: Colors.teal.shade200,
                    onSelected: (val) {
                      if (val) setState(() => _avatarStyle = style);
                    },
                  );
                }).toList(),
              ),
            ],
            
            if (_avatarStyle == 'custom')
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() { _avatarStyle = 'adventure'; _selectedImageBytes = null; }), 
                  icon: const Icon(Icons.close), label: const Text('Remove Upload')
                )
              ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),

            // --- MANDATORY FIELDS ---
            const Text('Mandatory Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal)),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              onChanged: (val) => setState(() {}), // Triggers avatar seed redraw
              decoration: const InputDecoration(labelText: 'Full Name *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email Address *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password *', border: OutlineInputBorder()),
            ),

            const SizedBox(height: 32),

            // --- OPTIONAL FIELDS ---
            const Text('Optional Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()),
            ),

            const SizedBox(height: 40),
            
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createAccount,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                child: _isLoading 
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white))
                    : const Text('Create Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40), // Bottom padding
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// BALANCES SCREEN (Liquid Glass Upgrade)
// ---------------------------------------------------------
class BalancesScreen extends StatelessWidget {
  final String groupId;
  const BalancesScreen({super.key, required this.groupId});

  Future<Map<String, dynamic>> _fetchSettlementsAndNames() async {
    final settlements = await getFinalSettlements(groupId);
    final profilesData = await Supabase.instance.client.from('profiles').select('id, display_name');
    final Map<String, String> nameMap = {};
    for (var p in profilesData) {
      nameMap[p['id']] = p['display_name'] ?? 'Unknown User';
    }
    return {'settlements': settlements, 'names': nameMap};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, // Lets the liquid background flow under the top bar!
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Completely invisible
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Settle Up', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ),
      body: Container(
        // THE LIQUID BACKGROUND
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F2027), // Deep space black
              Color(0xFF203A43), // Muted dark teal
              Color(0xFF2C5364), // Slate teal
            ],
          ),
        ),
        child: SafeArea(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _fetchSettlementsAndNames(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.tealAccent));
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
              }

              final data = snapshot.data!;
              final List<Settlement> settlements = data['settlements'];
              final Map<String, String> names = data['names'];

              // THE NEW BEAUTIFUL EMPTY STATE
              if (settlements.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: GlassCard(
                      height: 250,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.tealAccent.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.task_alt, size: 60, color: Colors.tealAccent),
                          ),
                          const SizedBox(height: 24),
                          const Text('All Settled Up!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 8),
                          Text(
                            'Nobody owes anything in this group.\nYou can relax!', 
                            textAlign: TextAlign.center, 
                            style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.7))
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: settlements.length,
                itemBuilder: (context, index) {
                  final settlement = settlements[index];
                  final String fromName = names[settlement.fromUser] ?? 'User';
                  final String toName = names[settlement.toUser] ?? 'User';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    // THE GLASS LIST ITEM
                    child: GlassCard(
                      padding: const EdgeInsets.all(4),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.tealAccent.withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
                          ),
                          child: const Icon(Icons.currency_exchange, color: Colors.tealAccent),
                        ),
                        title: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 16, color: Colors.white),
                            children: [
                              TextSpan(text: fromName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent)),
                              const TextSpan(text: ' pays '),
                              TextSpan(text: toName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        trailing: Text(
                          '₹${settlement.amount.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
// ---------------------------------------------------------
// RECORD PAYMENT SCREEN (Now with Category Tagging!)
// ---------------------------------------------------------
class RecordPaymentScreen extends StatefulWidget {
  final String groupId;
  
  const RecordPaymentScreen({super.key, required this.groupId});

  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen> {
  final TextEditingController _amountController = TextEditingController();
  bool _isLoading = false;
  String? _selectedUserId;

  Future<void> _savePaymentToCloud() async {
    if (_amountController.text.trim().isEmpty || _selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a user and enter a valid amount.'), backgroundColor: Colors.orange));
      return;
    }
    
    setState(() => _isLoading = true);

    try {
      // Silently strip commas so the math parser doesn't crash!
      final double amount = double.parse(_amountController.text.replaceAll(',', ''));
      
      // ---> NEW: STRICT PAYMENT VALIDATION <---
      if (amount <= 0) throw Exception('Payment amount must be greater than zero.');
      if (amount > 1000000) throw Exception('Amount exceeds the maximum allowed limit of ₹10,00,000 per transaction.');
      // ----------------------------------------
      
      final String myUserId = Supabase.instance.client.auth.currentUser!.id;

      // 1. Create the Expense record (Tagging it specifically as a 'Payment'!)
      final expenseResponse = await Supabase.instance.client
          .from('expenses')
          .insert({
            'group_id': widget.groupId,
            'paid_by': myUserId,
            'description': '💸 Payment / Settle Up',
            'amount': amount,
            'category': 'Payment', // <-- THE CRITICAL CHART FIX!
          })
          .select()
          .single();

      final String newExpenseId = expenseResponse['id'];

      // 2. Create the Split 
      await Supabase.instance.client.from('expense_splits').insert({
        'expense_id': newExpenseId,
        'user_id': _selectedUserId,
        'amount_owed': amount,
      });

      // 3. Log the Payment in the Activity Feed
      await Supabase.instance.client.from('activity_logs').insert({
        'expense_id': newExpenseId,
        'group_id': widget.groupId,
        'actor_id': myUserId,
        'action': 'created',
        'expense_description': '💸 Payment / Settle Up',
        'expense_amount': amount,
      });

      if (mounted) Navigator.pop(context);
      
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String myUserId = Supabase.instance.client.auth.currentUser!.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Record Payment'), backgroundColor: Colors.green.shade100),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.handshake, size: 80, color: Colors.green),
            const SizedBox(height: 24),
            
            // THE JOIN: Fetching real names for the dropdown, ignoring yourself
            FutureBuilder(
              future: Supabase.instance.client
                  .from('group_members')
                  .select('user_id, profiles(display_name)')
                  .eq('group_id', widget.groupId)
                  .neq('user_id', myUserId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final List<dynamic> members = snapshot.data as List<dynamic>;
                
                if (members.isEmpty) {
                  return const Text('No other members to pay!', textAlign: TextAlign.center);
                }

                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Who did you pay?', border: OutlineInputBorder()),
                  value: _selectedUserId,
                  // Explicitly typing it as <String> so Dart doesn't throw a fit!
                  items: members.map<DropdownMenuItem<String>>((m) {
                    final String realName = m['profiles']?['display_name'] ?? 'User ${m['user_id'].toString().substring(0, 4)}';
                    return DropdownMenuItem<String>(
                      value: m['user_id'] as String,
                      child: Text(realName),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedUserId = value),
                );
              },
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount Paid (₹)', border: OutlineInputBorder()),
            ),
            
            const SizedBox(height: 32),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _savePaymentToCloud,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                child: _isLoading 
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white))
                    : const Text('Save Payment', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ---------------------------------------------------------
// PRODUCTION PROFILE ARCHITECTURE (Name, Email, Phone, Password OTP, Avatar Selector, Self-Deletion)
// ---------------------------------------------------------
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _upiController = TextEditingController();

  bool _isLoading = false;
  bool _isFetching = true;
  String _currentAvatarStyle = 'adventure';
  String? _userId;

  // Available avatar options
  final List<String> _avatarStyles = ['adventure', 'bottts', 'pixel-art', 'lorelei', 'micah'];

  @override
  void initState() {
    super.initState();
    _loadUserIdentity();
  }

  Future<void> _loadUserIdentity() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      _userId = user.id;

      final profileData = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', _userId!)
          .maybeSingle();

      setState(() {
        _emailController.text = user.email ?? '';
        _phoneController.text = user.phone ?? '';
        if (profileData != null) {
          _nameController.text = profileData['display_name'] ?? '';
          _upiController.text = profileData['upi_id'] ?? '';
          _currentAvatarStyle = profileData['avatar_style'] ?? 'adventure';
        }
        _isFetching = false;
      });
    } catch (e) {
      setState(() => _isFetching = false);
    }
  }

  // --- TRADITIONAL SECURITY CORE FUNCTIONS via Supabase Auth ---
  Future<void> _updateIdentityCore() async {
    setState(() => _isLoading = true);
    try {
      // 1. Update Cloud Database Profile Data
      await Supabase.instance.client.from('profiles').upsert({
        'id': _userId!,
        'display_name': _nameController.text.trim(),
        'upi_id': _upiController.text.trim(),
        'avatar_style': _currentAvatarStyle,
      }, onConflict: 'id'); // Added onConflict here as well to be perfectly safe!

      // 2. Sync to Central Security Records ONLY if values actually changed
      final user = Supabase.instance.client.auth.currentUser;
      final newEmail = _emailController.text.trim();
      final newPhone = _phoneController.text.trim();

      bool emailChanged = newEmail.isNotEmpty && newEmail != (user?.email ?? '');
      bool phoneChanged = newPhone.isNotEmpty && newPhone != (user?.phone ?? '');

      // Only trigger the sensitive Auth update if a user actually typed new credentials
      if (emailChanged || phoneChanged) {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(
            email: emailChanged ? newEmail : null,
            phone: phoneChanged ? newPhone : null,
          ),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Identity parameters updated successfully!'), backgroundColor: Colors.teal),
        );
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerPasswordResetOTP() async {
    if (_emailController.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _emailController.text.trim(),
        redirectTo: 'https://bhavyaraichura.github.io/splitwise_clone/', // Link to your live dashboard
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password Reset secure token dispatched to your email!'), backgroundColor: Colors.blue),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _executePermanentSelfDestruct() async {
    bool confirm = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Account Permanently?'),
        content: const Text('This will instantly purge your access tokens, profile information, and ledger visibility. This action is irreversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('DELETE', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (!confirm) return;
    setState(() => _isLoading = true);

    try {
      // Execute explicit self deletion trigger
      await Supabase.instance.client.rpc('delete_authenticated_user_safely');
      await Supabase.instance.client.auth.signOut();
      
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      // Fallback if administrative RPC is configured strictly: log user out directly
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
      }
    }
  }
void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.teal),
              title: const Text('Upload from Album'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Album picker triggered')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.face, color: Colors.orange),
              title: const Text('Choose Avatar Style'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a style from the chips below!')));
              },
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    // Generate secure dynamic PNG avatar render endpoints using DiceBear
    String avatarUrl = 'https://api.dicebear.com/7.x/$_currentAvatarStyle/png?seed=${_nameController.text.isNotEmpty ? _nameController.text : "Bhavya"}';

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title: const Text('Account Control Center'), backgroundColor: Colors.teal.shade100),
      body: _isFetching
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- AVATAR MATRIX CONTROLLER ---
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _showImagePickerOptions,
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                height: 100, width: 100,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.teal.shade50),
                                child: ClipOval(child: Image.network(avatarUrl, fit: BoxFit.cover)),
                              ),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
                                child: const Icon(Icons.edit, size: 16, color: Colors.white),
                              )
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: _avatarStyles.map((style) {
                            final isSelected = _currentAvatarStyle == style;
                            return ChoiceChip(
                              label: Text(style),
                              selected: isSelected,
                              selectedColor: Colors.teal.shade200,
                              onSelected: (val) {
                                if (val) setState(() => _currentAvatarStyle = style);
                              },
                            );
                          }).toList(),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // --- ATTRIBUTE MANAGEMENT FIELDS ---
                  TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Display Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge))),
                  const SizedBox(height: 16),
                  TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Primary Email Verified Address', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email))),
                  const SizedBox(height: 16),
                  TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone Identifier (with country code)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
                  const SizedBox(height: 16),
                  TextField(controller: _upiController, decoration: const InputDecoration(labelText: 'Default UPI String Parameter', border: OutlineInputBorder(), prefixIcon: Icon(Icons.payment))),
                  
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _updateIdentityCore,
                    icon: _isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
                    label: const Text('Save Profile Updates'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                  
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _triggerPasswordResetOTP,
                    icon: const Icon(Icons.lock_reset, color: Colors.blue),
                    label: const Text('Send Password Reset OTP Email'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                  
                  const SizedBox(height: 40),
                  const Divider(color: Colors.redAccent),
                  TextButton.icon(
                    onPressed: _isLoading ? null : _executePermanentSelfDestruct,
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    label: const Text('Permanently Destroy Account', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            ),
    );
  }
}
// ---------------------------------------------------------
// CREATE GROUP SCREEN
// ---------------------------------------------------------
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;

  Future<void> _createGroupInCloud() async {
    if (_nameController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final String myUserId = Supabase.instance.client.auth.currentUser!.id;

      // 1. Create the group in the 'groups' table
      final groupResponse = await Supabase.instance.client
          .from('groups')
          .insert({
            'name': _nameController.text.trim(),
          })
          .select()
          .single(); 

      final String newGroupId = groupResponse['id'];

      // 2. Add yourself as the first member in 'group_members'
      await Supabase.instance.client.from('group_members').insert({
        'group_id': newGroupId,
        'user_id': myUserId,
      });

      // 3. Success! Go back to the dashboard
      if (mounted) {
        Navigator.pop(context, true); 
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Group'), backgroundColor: Colors.teal.shade100),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Icon(Icons.group_add, size: 80, color: Colors.teal),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Group Name (e.g., Goa Trip)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createGroupInCloud,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                child: _isLoading 
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white))
                    : const Text('Create Group', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ---------------------------------------------------------
// ADD MEMBER SCREEN
// ---------------------------------------------------------
class AddMemberScreen extends StatefulWidget {
  final String groupId;
  
  const AddMemberScreen({super.key, required this.groupId});

  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends State<AddMemberScreen> {
  bool _isLoading = false;
  bool _isFetching = true;
  
  List<dynamic> _availableProfiles = [];
  String? _selectedUserId;

  @override
  void initState() {
    super.initState();
    _fetchAvailableUsers();
  }

  Future<void> _fetchAvailableUsers() async {
    try {
      final String myId = Supabase.instance.client.auth.currentUser!.id;

      // 1. Get everyone currently in the group so we don't add duplicates
      final membersData = await Supabase.instance.client
          .from('group_members')
          .select('user_id')
          .eq('group_id', widget.groupId);
          
      final List<String> currentMemberIds = (membersData as List).map((m) => m['user_id'] as String).toList();

      // 2. Get your actual Friends List (instead of the global database)
      final myFriendGroups = await Supabase.instance.client
          .from('group_members')
          .select('group_id, groups!inner(type)')
          .eq('user_id', myId)
          .eq('groups.type', 'friend');

      if (myFriendGroups.isEmpty) {
        setState(() {
          _availableProfiles = [];
          _isFetching = false;
        });
        return;
      }

      final List<String> friendGroupIds = myFriendGroups.map((g) => g['group_id'] as String).toList();

      final friendsData = await Supabase.instance.client
          .from('group_members')
          .select('user_id, profiles(id, display_name)')
          .inFilter('group_id', friendGroupIds)
          .neq('user_id', myId);

      // 3. Filter the friends list to only show those NOT already in the group
      final available = friendsData.map((f) => f['profiles']).where((profile) {
        return !currentMemberIds.contains(profile['id']);
      }).toList();

      setState(() {
        _availableProfiles = available;
        if (available.isNotEmpty) {
          _selectedUserId = available.first['id'];
        }
        _isFetching = false;
      });
    } catch (error) {
      setState(() => _isFetching = false);
    }
  }

  Future<void> _addMemberToGroup() async {
    if (_selectedUserId == null) return;

    setState(() => _isLoading = true);

    try {
      // Create the bridge in the database!
      await Supabase.instance.client.from('group_members').insert({
        'group_id': widget.groupId,
        'user_id': _selectedUserId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member added successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Member'), backgroundColor: Colors.teal.shade100),
      body: _isFetching 
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.person_add, size: 80, color: Colors.teal),
                const SizedBox(height: 24),
                const Text(
                  'Select a user to add to this group:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                
                // If everyone is already in the group, show a message
                if (_availableProfiles.isEmpty)
                  const Text(
                    'No new users available to add!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                  )
                else
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Available Users', 
                      border: OutlineInputBorder()
                    ),
                    value: _selectedUserId,
                    items: _availableProfiles.map((profile) {
                      return DropdownMenuItem<String>(
                        value: profile['id'],
                        child: Text(profile['display_name'] ?? 'Unknown User'),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedUserId = value),
                  ),
                  
                const SizedBox(height: 32),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_isLoading || _availableProfiles.isEmpty) ? null : _addMemberToGroup,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                    child: _isLoading 
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white))
                        : const Text('Add to Group', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
// ---------------------------------------------------------
// GROUP CHARTS SCREEN (The Pie Chart Dashboard!)
// ---------------------------------------------------------
class GroupChartsScreen extends StatelessWidget {
  final String groupId;

  const GroupChartsScreen({super.key, required this.groupId});

  Future<Map<String, double>> _fetchCategoryTotals() async {
    final expensesData = await Supabase.instance.client
        .from('expenses')
        .select('category, amount')
        .eq('group_id', groupId);

    final Map<String, double> totals = {};
    for (var e in (expensesData as List)) {
      // Exclude "payments" from the pie chart so it only shows real expenses
      if (e['category'] == 'Payment') continue; 
      
      final String cat = e['category'] ?? 'General';
      final double amt = (e['amount'] as num).toDouble();
      totals[cat] = (totals.containsKey(cat) ? totals[cat]! : 0) + amt;
    }
    return totals;
  }

  // A helper function to assign specific colors to specific categories
  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Food': return Colors.orange;
      case 'Travel': return Colors.blue;
      case 'Rent': return Colors.red;
      case 'Entertainment': return Colors.purple;
      default: return Colors.teal; // General
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Spending Insights'), backgroundColor: Colors.teal.shade100),
      body: FutureBuilder<Map<String, double>>(
        future: _fetchCategoryTotals(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final totals = snapshot.data ?? {};
          if (totals.isEmpty || totals.values.every((v) => v == 0)) {
            return const Center(child: Text('No expenses recorded yet!'));
          }

          // Convert our totals dictionary into slices for the Pie Chart
          final List<PieChartSectionData> pieSections = totals.entries.map((entry) {
            return PieChartSectionData(
              color: _getCategoryColor(entry.key),
              value: entry.value,
              title: '${entry.key}\n₹${entry.value.toStringAsFixed(0)}',
              radius: 120, // Size of the pie slice
              titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            );
          }).toList();

          return Column(
            children: [
              const SizedBox(height: 40),
              const Text('Total Spending by Category', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              Expanded(
                child: PieChart(
                  PieChartData(
                    sections: pieSections,
                    centerSpaceRadius: 40, // Makes it a donut chart!
                    sectionsSpace: 2, // Tiny gap between slices
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }
}
// ---------------------------------------------------------
// ADD FRIEND SCREEN (Creates a 1-on-1 invisible group)
// ---------------------------------------------------------
class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  bool _isLoading = false;
  bool _isFetching = true;
  List<dynamic> _availableProfiles = [];
  String? _selectedUserId;

  @override
  void initState() {
    super.initState();
    _fetchAvailableUsers();
  }

  Future<void> _fetchAvailableUsers() async {
    try {
      final String myUserId = Supabase.instance.client.auth.currentUser!.id;
      // 1. Get your current friend groups
      final myFriendGroups = await Supabase.instance.client
          .from('group_members')
          .select('group_id, groups!inner(type)')
          .eq('user_id', myUserId)
          .eq('groups.type', 'friend');

      final List<String> friendGroupIds = myFriendGroups.map((g) => g['group_id'] as String).toList();

      // 2. Find IDs of people you are already friends with
      final existingFriends = await Supabase.instance.client
          .from('group_members')
          .select('user_id')
          .inFilter('group_id', friendGroupIds)
          .neq('user_id', myUserId);

      final Set<String> existingFriendIds = existingFriends.map((f) => f['user_id'] as String).toSet();

      // 3. Get everyone else in the database
      final allProfiles = await Supabase.instance.client.from('profiles').select().neq('id', myUserId);

      // 4. Filter out the people you are already friends with
      final availableProfiles = (allProfiles as List).where((p) => !existingFriendIds.contains(p['id'])).toList();

      setState(() {
        _availableProfiles = availableProfiles;
        if (availableProfiles.isNotEmpty) _selectedUserId = availableProfiles.first['id'];
        _isFetching = false;
      });
    } catch (error) {
      setState(() => _isFetching = false);
    }
  }

  Future<void> _addFriend() async {
    if (_selectedUserId == null) return;
    setState(() => _isLoading = true);

    try {
      final String myUserId = Supabase.instance.client.auth.currentUser!.id;

      // 1. Create the invisible "Friend" group
      final groupResponse = await Supabase.instance.client
          .from('groups')
          .insert({
            'name': 'Friends', // The UI will ignore this and show their real name instead
            'type': 'friend',            // <-- The magic tag!
          })
          .select()
          .single();

      final String newGroupId = groupResponse['id'];

      // 2. Add exactly you and them to this private group
      await Supabase.instance.client.from('group_members').insert([
        {'group_id': newGroupId, 'user_id': myUserId},
        {'group_id': newGroupId, 'user_id': _selectedUserId},
      ]);

      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add a Friend'), backgroundColor: Colors.teal.shade100),
      body: _isFetching 
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.person_add_alt_1, size: 80, color: Colors.teal),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Select a User', border: OutlineInputBorder()),
                  value: _selectedUserId,
                  items: _availableProfiles.map((profile) {
                    return DropdownMenuItem<String>(
                      value: profile['id'],
                      child: Text(profile['display_name'] ?? 'Unknown User'),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedUserId = value),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _addFriend,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                    child: _isLoading 
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white))
                        : const Text('Start Splitting', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
// ---------------------------------------------------------
// AD-HOC SPLIT SCREEN (Select Multiple Friends dynamically)
// ---------------------------------------------------------
class AdhocSplitScreen extends StatefulWidget {
  const AdhocSplitScreen({super.key});
  @override
  State<AdhocSplitScreen> createState() => _AdhocSplitScreenState();
}

class _AdhocSplitScreenState extends State<AdhocSplitScreen> {
  bool _isLoading = false;
  List<dynamic> _allUsers = [];
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    try {
      final String myId = Supabase.instance.client.auth.currentUser!.id;
      
      // 1. Find all groups that are specifically "friend" connections for you
      final myFriendGroups = await Supabase.instance.client
          .from('group_members')
          .select('group_id, groups!inner(type)')
          .eq('user_id', myId)
          .eq('groups.type', 'friend');

      if (myFriendGroups.isEmpty) {
        setState(() => _allUsers = []);
        return;
      }

      final List<String> friendGroupIds = myFriendGroups.map((g) => g['group_id'] as String).toList();

      // 2. Fetch the profiles of the *other* people in those specific groups
      final friendsData = await Supabase.instance.client
          .from('group_members')
          .select('user_id, profiles(id, display_name)')
          .inFilter('group_id', friendGroupIds)
          .neq('user_id', myId);

      // 3. Clean up the data structure to match what the UI expects
      final List<dynamic> parsedFriends = friendsData.map((f) => f['profiles']).toList();

      setState(() => _allUsers = parsedFriends);
    } catch (e) {
      setState(() => _allUsers = []);
    }
  }

  Future<void> _startAdhocExpense() async {
    if (_selectedIds.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final myId = Supabase.instance.client.auth.currentUser!.id;

      // 1. Create the invisible Adhoc Group
      final groupResponse = await Supabase.instance.client.from('groups').insert({
        'name': 'Ad-hoc Split',
        'type': 'adhoc', // Hides it from the Dashboard tabs!
      }).select().single();

      // 2. Add everyone selected + yourself
      List<Map<String, dynamic>> members = _selectedIds.map((id) => {'group_id': groupResponse['id'], 'user_id': id}).toList();
      members.add({'group_id': groupResponse['id'], 'user_id': myId});
      
      await Supabase.instance.client.from('group_members').insert(members);

      // 3. Jump straight into the Expense Screen
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (context) => AddExpenseScreen(groupId: groupResponse['id'])
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Split with Friends'), backgroundColor: Colors.teal.shade100),
      body: _allUsers.isEmpty 
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _allUsers.length,
              itemBuilder: (context, index) {
                final user = _allUsers[index];
                final isSelected = _selectedIds.contains(user['id']);
                return CheckboxListTile(
                  title: Text(user['display_name'] ?? 'Unknown'),
                  value: isSelected,
                  activeColor: Colors.teal,
                  onChanged: (bool? val) {
                    setState(() {
                      val == true ? _selectedIds.add(user['id']) : _selectedIds.remove(user['id']);
                    });
                  },
                );
              },
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _isLoading || _selectedIds.isEmpty ? null : _startAdhocExpense,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(50)),
          child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Proceed to Expense'),
        ),
      ),
    );
  }
}
// ---------------------------------------------------------
// EXPENSE DETAIL & AUDIT SCREEN (The Ledger View)
// ---------------------------------------------------------

class ExpenseDetailScreen extends StatefulWidget {
  final String expenseId;
  final String groupId;

  const ExpenseDetailScreen({super.key, required this.expenseId, required this.groupId});

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  Map<String, dynamic>? _expenseData;
  List<dynamic> _activityLogs = [];
  Map<String, String> _profileNames = {}; 
  bool _isLoading = true;
  
  final TextEditingController _commentController = TextEditingController(); 

  @override
  void initState() {
    super.initState();
    _fetchCompleteAuditTrail();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _fetchCompleteAuditTrail() async {
    try {
      final expenseResponse = await Supabase.instance.client
          .from('expenses')
          .select()
          .eq('id', widget.expenseId)
          .maybeSingle();

      final logsResponse = await Supabase.instance.client
          .from('activity_logs')
          .select()
          .eq('expense_id', widget.expenseId)
          .order('created_at', ascending: false);

      final profilesResponse = await Supabase.instance.client
          .from('profiles')
          .select('id, display_name');

      Map<String, String> namesMap = {};
      for (var p in (profilesResponse as List)) {
        namesMap[p['id'].toString()] = p['display_name']?.toString() ?? 'Unknown User';
      }

      setState(() {
        _expenseData = expenseResponse;
        _activityLogs = logsResponse as List<dynamic>;
        _profileNames = namesMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmAndDelete() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Expense?'),
          content: const Text('Are you sure you want to delete this expense? This action can be undone later via the activity feed.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.black)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _deleteExpense();
    }
  }

  Future<void> _deleteExpense() async {
    try {
      await Supabase.instance.client
          .from('expenses')
          .update({'is_deleted': true})
          .eq('id', widget.expenseId);

      await Supabase.instance.client.from('activity_logs').insert({
        'group_id': widget.groupId, // <--- THE CRITICAL FIX
        'expense_id': widget.expenseId,
        'actor_id': Supabase.instance.client.auth.currentUser!.id,
        'action': 'deleted',
        'description': 'deleted the expense',
        'expense_description': _expenseData?['description'], 
        'expense_amount': _expenseData?['amount'],
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense deleted successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      // If it fails again, it will now pop up and tell us why!
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _recoverExpense() async {
    try {
      await Supabase.instance.client
          .from('expenses')
          .update({'is_deleted': false})
          .eq('id', widget.expenseId);

      await Supabase.instance.client.from('activity_logs').insert({
        'group_id': widget.groupId, // <--- THE CRITICAL FIX
        'expense_id': widget.expenseId,
        'actor_id': Supabase.instance.client.auth.currentUser!.id,
        'action': 'recovered',
        'description': 'recovered the expense',
        'expense_description': _expenseData?['description'], 
        'expense_amount': _expenseData?['amount'],
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense recovered successfully!')),
        );
        Navigator.pop(context); 
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _postComment() async {
    if (_commentController.text.trim().isEmpty) return;

    final commentText = _commentController.text.trim();
    _commentController.clear(); 

    try {
      await Supabase.instance.client.from('activity_logs').insert({
        'group_id': widget.groupId, // <--- THE CRITICAL FIX
        'expense_id': widget.expenseId,
        'actor_id': Supabase.instance.client.auth.currentUser!.id,
        'action': 'commented',
        'description': commentText,
      });

      _fetchCompleteAuditTrail();
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
    final bool isDeleted = _expenseData?['is_deleted'] == true || _expenseData?['deleted_at'] != null;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Expense Details'),
        backgroundColor: Colors.teal.shade100,
        actions: [
          // Only show the Edit button if the expense is active
          if (!isDeleted) 
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => AddExpenseScreen(groupId: widget.groupId, expenseToEdit: _expenseData)),
                ).then((_) => _fetchCompleteAuditTrail());
              },
            ),
            
          // THE SWAP: Show Delete if active, show Recover if deleted!
          if (!isDeleted)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'Delete Expense',
              onPressed: _confirmAndDelete, 
            )
          else
            IconButton(
              icon: const Icon(Icons.restore, color: Colors.green),
              tooltip: 'Recover Expense',
              onPressed: _recoverExpense, 
            ),
        ],
      ),
      body: Column( 
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade300)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          Icon(isDeleted ? Icons.delete_outline : Icons.receipt_long, size: 60, color: isDeleted ? Colors.red : Colors.teal),
                          const SizedBox(height: 16),
                          Text(
                            _expenseData?['description'] ?? 'Unknown Expense', 
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, decoration: isDeleted ? TextDecoration.lineThrough : null)
                          ),
                          const SizedBox(height: 8),
                          Text('₹${_expenseData?['amount'] ?? 0}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.teal)),
                          if (isDeleted)
                             const Padding(padding: EdgeInsets.only(top: 8), child: Text('This expense was deleted.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  const Text('Audit Trail & Comments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  
                  ..._activityLogs.map((log) {
                    String actionText = log['action'] ?? 'unknown';
                    String actorId = log['actor_id']?.toString() ?? '';
                    String actorName = _profileNames[actorId] ?? 'Someone';
                    
                    String rawDate = log['created_at'].toString();
                    String cleanDate = rawDate.length > 16 ? rawDate.substring(0, 16).replaceAll('T', ' ') : rawDate;

                    if (actionText == 'commented') {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Colors.purpleAccent, child: Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20)),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(actorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              Text(cleanDate, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                          subtitle: Text(log['description'] ?? '', style: const TextStyle(fontSize: 16, color: Colors.black87)),
                        ),
                      );
                    }

                    Color badgeColor = actionText == 'created' ? Colors.green : (actionText == 'deleted' ? Colors.red : Colors.blue);
                    return ListTile(
                      leading: CircleAvatar(backgroundColor: badgeColor.withOpacity(0.2), child: Icon(Icons.history, color: badgeColor)),
                      title: Text('$actorName $actionText this expense'),
                      subtitle: Text(cleanDate, style: const TextStyle(fontSize: 12)),
                    );
                  }).toList(),
                  
                  const SizedBox(height: 24),
                  // (The big green Recover button has been completely removed from here)
                ],
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.teal,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _postComment,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// ---------------------------------------------------------
// USER LEDGER SCREEN (1-on-1 Consolidated Audit Trail)
// ---------------------------------------------------------
class UserLedgerScreen extends StatefulWidget {
  final String targetUserId;
  final String targetUserName;

  const UserLedgerScreen({super.key, required this.targetUserId, required this.targetUserName});

  @override
  State<UserLedgerScreen> createState() => _UserLedgerScreenState();
}

class _UserLedgerScreenState extends State<UserLedgerScreen> {
  
  Future<List<Map<String, dynamic>>> _fetchMutualLedger() async {
    final myUserId = Supabase.instance.client.auth.currentUser!.id;
    
    // 1. Fetch expenses where I paid, and they owe me a cut
    final myPayments = await Supabase.instance.client
        .from('expense_splits')
        .select('amount_owed, expenses!inner(id, description, amount, created_at, paid_by, group_id, deleted_at)')
        .eq('user_id', widget.targetUserId)
        .neq('expenses.is_deleted', true)
        .eq('expenses.paid_by', myUserId)
        .isFilter('expenses.deleted_at', null);

    // 2. Fetch expenses where they paid, and I owe them a cut
    final theirPayments = await Supabase.instance.client
        .from('expense_splits')
        .select('amount_owed, expenses!inner(id, description, amount, created_at, paid_by, group_id, deleted_at)')
        .eq('user_id', myUserId)
        .neq('expenses.is_deleted', true)
        .eq('expenses.paid_by', widget.targetUserId)
        .isFilter('expenses.deleted_at', null);

    List<Map<String, dynamic>> consolidated = [];

    // Format my payments
    for (var p in (myPayments as List)) {
      consolidated.add({
        'expense_id': p['expenses']['id'],
        'group_id': p['expenses']['group_id'],
        'description': p['expenses']['description'],
        'split_amount': p['amount_owed'],
        'is_owed_to_me': true,
        'created_at': p['expenses']['created_at']
      });
    }

    // Format their payments
    for (var p in (theirPayments as List)) {
      consolidated.add({
        'expense_id': p['expenses']['id'],
        'group_id': p['expenses']['group_id'],
        'description': p['expenses']['description'],
        'split_amount': p['amount_owed'],
        'is_owed_to_me': false,
        'created_at': p['expenses']['created_at']
      });
    }

    // Sort the timeline by newest first
    consolidated.sort((a, b) => DateTime.parse(b['created_at']).compareTo(DateTime.parse(a['created_at'])));
    
    return consolidated;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title: Text('Ledger with ${widget.targetUserName}'), backgroundColor: Colors.teal.shade100),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchMutualLedger(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          
          final ledger = snapshot.data ?? [];
          
          if (ledger.isEmpty) {
            return const Center(child: Text('No shared expenses found.', style: TextStyle(color: Colors.grey)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: ledger.length,
            itemBuilder: (context, index) {
              final item = ledger[index];
              final bool isOwedToMe = item['is_owed_to_me'];
              final bool isPayment = item['description'] == '💸 Payment / Settle Up';
              
              final String rawDate = item['created_at'].toString();
              final String cleanDate = rawDate.length > 10 ? rawDate.substring(0, 10) : rawDate;

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                child: ListTile(
                  onTap: () {
                    // Dive directly into the core expense view!
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ExpenseDetailScreen(
                          expenseId: item['expense_id'],
                          groupId: item['group_id']
                        )
                      )
                    ).then((_) => setState(() {}));
                  },
                  leading: CircleAvatar(
                    backgroundColor: isPayment ? Colors.green.shade50 : (isOwedToMe ? Colors.teal.shade50 : Colors.red.shade50),
                    child: Icon(isPayment ? Icons.payment : Icons.receipt_long, color: isPayment ? Colors.green : (isOwedToMe ? Colors.teal : Colors.red)),
                  ),
                  title: Text(item['description'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(cleanDate),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(isOwedToMe ? 'You lent' : 'You borrowed', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      Text(
                        '₹${(item['split_amount'] as num).toStringAsFixed(2)}', 
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isOwedToMe ? Colors.teal : Colors.red)
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------
// UI ENGINE: THE LIQUID GLASS CARD
// ---------------------------------------------------------
class GlassCard extends StatelessWidget {
  final Widget child;
  final double width;
  final double height;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap; // <--- We added the ability to receive clicks

  const GlassCard({
    super.key,
    required this.child,
    this.width = double.infinity,
    this.height = double.infinity,
    this.padding = const EdgeInsets.all(16.0),
    this.onTap, // <--- Added to the constructor
  });

  @override
  Widget build(BuildContext context) {
    // We wrap the whole thing in a GestureDetector so it registers your taps!
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: width,
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08), // Frosted glass opacity
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 30,
                  spreadRadius: -5,
                )
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}