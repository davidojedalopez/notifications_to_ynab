List<Map<String, String>> packages = [
  {
    'packageName': 'com.nu.production',
    'displayName': 'Nu',
    'amountRegex': r'\$([\d,]+(\.\d{1,2})?)',
    'payeeRegex': r'Compraste en ([A-Z\s]+) con tu tarjeta',
    'chargeEventRegex': r'^Compra aprobada',
  },
  {
    'packageName': 'com.bancomer.mbanking',
    'displayName': 'BBVA',
    'amountRegex': r'\$([\d,]+(\.\d{1,2})?)',
    'payeeRegex': r'COMPRA TDC EN ([A-Z\s]+)',
    'chargeEventRegex': r'^Compra en'
  },
];
