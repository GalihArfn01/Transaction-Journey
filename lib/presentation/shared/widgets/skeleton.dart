import 'package:flutter/material.dart';

/// Satu blok skeleton (placeholder loading) dengan denyut fade halus.
/// Dipakai menggantikan CircularProgressIndicator agar layout TIDAK
/// loncat saat data terisi — konten skeleton menempati ruang yang sama
/// dengan konten aslinya.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({required this.width, required this.height, super.key});

  final double width;
  final double height;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Kartu tujuan/transaksi skeleton: avatar bulat + dua baris teks + bar.
class SkeletonListCard extends StatelessWidget {
  const SkeletonListCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                SkeletonBox(width: 40, height: 40),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(width: 120, height: 16)),
              ],
            ),
            SizedBox(height: 12),
            SkeletonBox(width: 200, height: 12),
            SizedBox(height: 8),
            SkeletonBox(width: 260, height: 8),
          ],
        ),
      ),
    );
  }
}
