import 'package:flutter/material.dart';

import '../../../app/app_theme.dart'
    show AppGradients, AppRadii, AppShadows;

/// SATU bahasa kartu untuk seluruh aplikasi (hasil audit langkah 1).
///
/// Aturan pakai — pilih varian sesuai peran konten, JANGAN mengarang
/// dekorasi kartu baru di halaman:
///
/// - [AppCard.hero]: SATU per layar, untuk angka/judul terpenting
///   (Total Saldo, Total Terkumpul). Selalu gradient primary + teks
///   terang. Kalau satu layar butuh dua "hero", desainnya yang salah —
///   turunkan salah satunya ke `standard`.
/// - [AppCard.standard]: isi umum (daftar, chart, form ringkas, pratinjau).
///   Putih + border BIRU tipis + shadow kartu. Varian default bila ragu.
/// - [AppCard.group]: deretan seksi sejenis dalam SATU wadah (judul +
///   konten dipisah divider otomatis) — untuk menggabung kartu-kartu yang
///   struktur judul-kontennya seragam (mis. seksi-seksi Analytics).
///   Jangan pakai untuk konten heterogen (chart + list panjang) atau
///   untuk satu anak saja (pakai `standard`).
///
/// Semua varian memakai token ([AppRadii.cardBorder], [AppShadows]) —
/// angka radius/shadow/border TIDAK boleh ditulis di sini maupun di
/// halaman. Margin diserahkan ke pemanggil (halaman yang tahu konteks
/// list-nya); padding isi punya default wajar per varian.
class AppCard extends StatelessWidget {
  /// Kartu standar: permukaan terang + border + shadow kartu.
  const AppCard.standard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
  })  : _variant = _AppCardVariant.standard,
        title = null,
        children = null,
        gradient = null;

  /// Kartu hero: gradient primary + shadow hero. Satu per layar.
  const AppCard.hero({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.onTap,
    this.gradient = AppGradients.hero,
  })  : _variant = _AppCardVariant.hero,
        title = null,
        children = null;

  /// Grup seksi: satu wadah berisi [title] opsional + [children] yang
  /// otomatis dipisah divider. Minimal 2 anak (1 anak = `standard`).
  const AppCard.group({
    super.key,
    required this.children,
    this.title,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
  })  : _variant = _AppCardVariant.group,
        child = null,
        gradient = null;

  final _AppCardVariant _variant;
  final Widget? child;
  final List<Widget>? children;
  final String? title;
  final Gradient? gradient;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final BoxDecoration decoration = switch (_variant) {
      _AppCardVariant.hero => BoxDecoration(
          gradient: gradient,
          borderRadius: AppRadii.cardBorder,
          boxShadow: AppShadows.hero(scheme),
        ),
      _AppCardVariant.standard || _AppCardVariant.group => BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: AppRadii.cardBorder,
          // Border biru 2px (primary 80%) — pembeda dari border
          // abu outlineVariant yang dipakai elemen lain.
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.8),
            width: 2,
          ),
          boxShadow: AppShadows.card(scheme),
        ),
    };

    final TextStyle? titleStyle =
        Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            );

    final Widget content = switch (_variant) {
      _AppCardVariant.hero || _AppCardVariant.standard => Padding(
          padding: padding,
          child: child!,
        ),
      _AppCardVariant.group => Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (title != null) ...<Widget>[
                Text(title!, style: titleStyle),
                const SizedBox(height: 12),
              ],
              for (int i = 0; i < children!.length; i++) ...<Widget>[
                if (i > 0)
                  Divider(
                    height: 32,
                    thickness: 1,
                    indent: 16,
                    endIndent: 16,
                    color: scheme.outlineVariant,
                  ),
                children![i],
              ],
            ],
          ),
        ),
    };

    final VoidCallback? tap = onTap;
    final Widget body = tap == null
        ? content
        // Material transparan + clip supaya ripple mengikuti radius.
        : Material(
            color: Colors.transparent,
            borderRadius: AppRadii.cardBorder,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: AppRadii.cardBorder,
              onTap: tap,
              child: content,
            ),
          );

    final Widget card = Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: body,
    );
    final EdgeInsetsGeometry? margin = this.margin;
    if (margin == null) return card;
    return Padding(padding: margin, child: card);
  }
}

enum _AppCardVariant { standard, hero, group }
