/// Representasi uang.
///
/// Semua nilai finansial disimpan sebagai [int] rupiah utuh (minor-unit
/// strategi). Ini menghilangkan seluruh kelas bug floating point karena
/// operasi int bersifat eksak. Rupiah secara praktis tidak menggunakan
/// pecahan sen, sehingga presisi 1 unit = Rp1 sudah cukup dan aman.
library;

const int rupiahUnitScale = 1;

extension MoneyInt on int {
  bool get isMoneyPositive => this > 0;
  bool get isMoneyNonNegative => this >= 0;
}
