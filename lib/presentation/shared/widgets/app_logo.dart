import 'package:flutter/material.dart';

/// Logo aplikasi — dipakai di lock screen (menggantikan ikon gembok) dan
/// tempat lain yang butuh branding singkat.
///
/// Sumber gambar: `assets/icon/app_icon.png`, disalin dari ikon launcher
/// asli aplikasi (`android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`)
/// supaya konsisten dengan ikon yang dilihat pengguna di layar utama HP —
/// BUKAN logo buatan/reka-reka. Kalau launcher icon diganti di kemudian
/// hari, salin ulang file yang sama ke `assets/icon/app_icon.png` supaya
/// tetap sinkron (satu titik ubah ini otomatis berlaku ke semua tempat
/// yang memakai [AppLogo]).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/icon/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
