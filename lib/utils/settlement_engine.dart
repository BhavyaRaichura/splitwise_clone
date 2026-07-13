import 'package:supabase_flutter/supabase_flutter.dart';

// 1. Data Structure for a user's current standing
class UserBalance {
  String userId;
  double netBalance;

  UserBalance({required this.userId, required this.netBalance});
}

// 2. Data Structure for the final instructions (Who pays whom)
class Settlement {
  String fromUser;
  String toUser;
  double amount;

  // The rogue network call has been removed from here!

  Settlement({required this.fromUser, required this.toUser, required this.amount});
}

// 3. The Algorithm: Calculates the most efficient way to settle debts
List<Settlement> calculateSettlements(List<UserBalance> balances) {
  List<UserBalance> debtors = balances.where((b) => b.netBalance < 0).toList();
  List<UserBalance> creditors = balances.where((b) => b.netBalance > 0).toList();

  debtors.sort((a, b) => a.netBalance.compareTo(b.netBalance)); 
  creditors.sort((a, b) => b.netBalance.compareTo(a.netBalance)); 

  List<Settlement> settlements = [];
  int i = 0; 
  int j = 0; 

  while (i < debtors.length && j < creditors.length) {
    double debt = -debtors[i].netBalance;
    double credit = creditors[j].netBalance;

    double settledAmount = debt < credit ? debt : credit;

    settlements.add(Settlement(
      fromUser: debtors[i].userId,
      toUser: creditors[j].userId,
      amount: settledAmount,
    ));

    debtors[i].netBalance += settledAmount;
    creditors[j].netBalance -= settledAmount;

    if (debtors[i].netBalance == 0) i++;
    if (creditors[j].netBalance == 0) j++;
  }

  return settlements;
}

// 4. The Aggregator: Upgraded to calculate dynamic Co-Payers!
Future<List<Settlement>> getFinalSettlements(String groupId) async {
  final response = await Supabase.instance.client
      .from('expenses')
      // Pulls the new co-payer JSON column
      .select('paid_by, amount, payer_amounts, expense_splits(user_id, amount_owed)')
      .neq('is_deleted', true)
      .eq('group_id', groupId);

  Map<String, double> balances = {};

  for (var expense in response) {
    // --- CO-PAY ENGINE MIGRATION ---
    if (expense['payer_amounts'] != null) {
      // Loop through every person who chipped money in for this single bill
      Map<String, dynamic> payerAmounts = expense['payer_amounts'];
      payerAmounts.forEach((userId, amountPaid) {
        double amt = (amountPaid as num).toDouble();
        balances[userId] = (balances[userId] ?? 0) + amt;
      });
    } else {
      // LEGACY FALLBACK: If old records don't have a JSON map, credit the single payer
      String paidBy = expense['paid_by'];
      double totalAmount = (expense['amount'] as num).toDouble();
      balances[paidBy] = (balances[paidBy] ?? 0) + totalAmount;
    }

    // --- DEBIT LOGIC (Stays pristine) ---
    List splits = expense['expense_splits'];
    for (var split in splits) {
      String userId = split['user_id'];
      double owed = (split['amount_owed'] as num).toDouble();
      
      balances[userId] = (balances[userId] ?? 0) - owed;
    }
  }

  List<UserBalance> userBalances = balances.entries
      .map((e) => UserBalance(userId: e.key, netBalance: e.value))
      .toList();

  return calculateSettlements(userBalances);
}