import 'package:flutter/material.dart';

/// Registry icon berbasis key string (disimpan di DB, bukan objek UI).
IconData appIconForKey(String? key) => kAppIcons[key] ?? Icons.category;

const Map<String, IconData> kAppIcons = <String, IconData>{
  'restaurant': Icons.restaurant,
  'commute': Icons.commute,
  'shopping_bag': Icons.shopping_bag,
  'receipt_long': Icons.receipt_long,
  'movie': Icons.movie,
  'medical_services': Icons.medical_services,
  'school': Icons.school,
  'wifi': Icons.wifi,
  'smartphone': Icons.smartphone,
  'home_work': Icons.home_work,
  'savings': Icons.savings,
  'more_horiz': Icons.more_horiz,
  'payments': Icons.payments,
  'stars': Icons.stars,
  'laptop_mac': Icons.laptop_mac,
  'storefront': Icons.storefront,
  'trending_up': Icons.trending_up,
  'redeem': Icons.redeem,
  'category': Icons.category,
  'wallet': Icons.wallet,
  'account_balance': Icons.account_balance,
  'account_balance_wallet': Icons.account_balance_wallet,
  'credit_card': Icons.credit_card,
  'credit_score': Icons.credit_score,
};
