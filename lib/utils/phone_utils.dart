String convertPhoneToPseudoEmail(String phone) {
  // Remove all non-digit characters and return a stable pseudo-email used for phone logins
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  return '$digits@phone.twospace';
}
