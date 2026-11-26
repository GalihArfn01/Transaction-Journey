import 'package:flutter/material.dart';

import '../../../app/app_theme.dart';

/// Dropdown seragam untuk SELURUH aplikasi.
///
/// `DropdownButtonFormField` menyimpan hampir semua gaya **menu** terbukanya
/// di parameter widget, bukan di `ThemeData` (Flutter 3.27 belum punya tema
/// khusus dropdown). Akibatnya sebelum widget ini ada tiap halaman menulis
/// ulang gayanya sendiri dan hasilnya berbeda-beda: menu berlatar
/// `canvasColor` dengan sudut nyaris siku (radius bawaan 2 px) di sebagian
/// halaman, menu berlatar permukaan kartu di halaman lain, panah
/// `arrow_drop_down` di sini dan `expand_more` di sana, sampai teks pilihan
/// panjang yang terpotong karena barisnya tidak melebar.
///
/// Widget ini menyatukan keempat hal itu:
///
///  1. `dropdownColor` — `surfaceContainerLowest`, permukaan yang sama
///     dengan kartu, dialog, dan bottom sheet.
///  2. `borderRadius` — token [AppRadii.field], bukan 2 px bawaan Flutter.
///  3. `icon` — `Icons.expand_more` bergaris 20 px senada `iconTheme`
///     aplikasi dan tile tanggal di form anggaran/transaksi berulang.
///  4. [isExpanded] — baris melebar penuh sehingga nama rekening/kategori
///     yang panjang tidak memotong atau meluber keluar field.
///
/// Gaya **field**-nya sendiri tetap milik halaman lewat [decoration] (beberapa
/// form punya bahasa sendiri, mis. dropdown telanjang di dalam kartu putih
/// halaman transaksi). Bila [decoration] dibiarkan kosong, dekorasi bawaan
/// `inputDecorationTheme` aplikasi yang dipakai — termasuk cincin fokus
/// primary.
///
/// Jangan pakai `DropdownButtonFormField` langsung di halaman baru; pakai
/// widget ini supaya perbaikan gaya dropdown cukup dilakukan di satu tempat.
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.decoration,
    this.validator,
    this.isExpanded = true,
  });

  /// Nilai terpilih. `null` dipakai untuk placeholder seperti item "Semua".
  final T? value;

  /// Daftar pilihan, sudah termasuk item kosong/placeholder bila ada.
  final List<DropdownMenuItem<T>> items;

  /// `null` membuat field nonaktif (mis. jenis rekening yang tidak boleh
  /// diubah saat mode edit).
  final ValueChanged<T?>? onChanged;

  /// Dekorasi khusus halaman; `null` = ikut `inputDecorationTheme`.
  final InputDecoration? decoration;

  final FormFieldValidator<T>? validator;

  /// `true` (bawaan): teks pilihan melebar mengisi field.
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      isExpanded: isExpanded,
      // Gaya teks isi field: sama dengan nilai `TextFormField` di sebelahnya
      // (bawaan Flutter memakai titleMedium yang lebih tebal).
      style: theme.textTheme.bodyLarge,
      icon: Icon(Icons.expand_more, size: 20, color: scheme.onSurfaceVariant),
      dropdownColor: scheme.surfaceContainerLowest,
      borderRadius: AppRadii.fieldBorder,
      decoration: decoration,
    );
  }
}
