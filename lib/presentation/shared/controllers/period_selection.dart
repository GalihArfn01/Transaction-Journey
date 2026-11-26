import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/period.dart';

/// Pilihan periode aktif + rentang custom opsional.
class PeriodSelection {
  const PeriodSelection(this.type, {this.customStart, this.customEnd});

  final PeriodType type;
  final DateTime? customStart;
  final DateTime? customEnd;

  /// Rentang efektif inklusif-eksklusif relatif terhadap [now].
  DateRange resolve(DateTime now) {
    if (type == PeriodType.all) {
      return Periods.allRange();
    }
    return Periods.rangeFor(
      type,
      now: now,
      customRange: type == PeriodType.custom
          ? DateRange(
              start: customStart ?? Periods.startOfDay(now),
              end: customEnd ?? Periods.startOfNextDay(now),
            )
          : null,
    );
  }

  PeriodSelection copyWith({
    PeriodType? type,
    DateTime? customStart,
    DateTime? customEnd,
  }) =>
      PeriodSelection(
        type ?? this.type,
        customStart: customStart ?? this.customStart,
        customEnd: customEnd ?? this.customEnd,
      );
}

/// Kontroler global pilihan periode — dipakai Dashboard, Riwayat, Analisis
/// agar filter konsisten di seluruh aplikasi.
class PeriodSelectionController extends Notifier<PeriodSelection> {
  @override
  PeriodSelection build() => const PeriodSelection(PeriodType.thisMonth);

  void select(PeriodType type) => state = PeriodSelection(type);

  void selectCustom(DateTime start, DateTime end) => state = PeriodSelection(
        PeriodType.custom,
        customStart: Periods.startOfDay(start),
        customEnd: Periods.startOfNextDay(end),
      );
}

final NotifierProvider<PeriodSelectionController, PeriodSelection>
    periodSelectionProvider =
    NotifierProvider<PeriodSelectionController, PeriodSelection>(
  PeriodSelectionController.new,
);
