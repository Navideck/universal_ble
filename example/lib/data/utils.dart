bool isSystemService(String uuid) {
  final normalized = uuid.toUpperCase().replaceAll('-', '');
  return normalized == '00001800' ||
      normalized == '00001801' ||
      normalized == '0000180A' ||
      normalized.startsWith('000018');
}
