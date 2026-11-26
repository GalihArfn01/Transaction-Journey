import 'package:flutter/material.dart';

/// Chip filter 3D senada tema (dipakai lintas halaman: dashboard,
/// transaksi, kategori, notifikasi, ekspor).
///
/// Warna SELALU diturunkan dari `ColorScheme.primary` tema — tanpa aksen
/// neon per-item, supaya selaras dengan keseluruhan desain (hero gradient
/// biru, kartu putih). Yang TERPILIH tampil sebagai tombol 3D penuh
/// (gradasi primary + teks putih + bayangan); yang tidak terpilih tampil
/// terang (permukaan putih, teks/ikon/bingkai biru tua).
///
/// Kesan 3D dibuat dari DUA lapis (teknik tombol mainan): lapisan belakang
/// GELAP penuh yang mengintip 3px di bawah badan + badan bergradasi.
/// Sengaja TIDAK memakai `Border(bottom: ...)` + `borderRadius` — Flutter
/// menegaskan itu saat paint ("borderRadius hanya untuk border seragam").
///
/// CATATAN ukuran: widget ini TIDAK membawa padding luar (tanpa margin) —
/// pemanggil yang mengatur jarak (baris fixed-height seperti riwayat 56px
/// & kategori 52px hanya muat bila chip ~35px; lihat padding di bawah).
class Colorful3DChip extends StatelessWidget {
  const Colorful3DChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  /// Varian gelap/terang primary untuk sisi bawah & gradasi.
  static Color _shade(Color c, double amount) {
    final HSLColor hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color accent = scheme.primary;
    final Color dark = _shade(accent, -0.18);
    final Color light = _shade(accent, 0.12);
    final IconData? iconData = icon;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: <Widget>[
          // Lapisan sisi bawah 3D: mengintip di bawah badan.
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: dark,
                borderRadius: BorderRadius.circular(999),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: accent.withValues(
                      alpha: selected ? 0.35 : 0.15,
                    ),
                    blurRadius: selected ? 8 : 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
          // Badan tombol (terangkat 3px dari sisi bawahnya).
          Container(
            margin: const EdgeInsets.only(bottom: 3),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[light, accent],
                    )
                  : null,
              color: selected ? null : scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(999),
              // Border.all SERAGAM — aman dipakai bersama borderRadius.
              border: selected
                  ? null
                  : Border.all(
                      color: accent.withValues(alpha: 0.45),
                    ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (iconData != null) ...<Widget>[
                  Icon(
                    iconData,
                    size: 16,
                    color: selected ? Colors.white : dark,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: selected ? Colors.white : dark,
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
