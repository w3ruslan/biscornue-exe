// lib/print_spooler_windows.dart
// Windows yazıcı spooler'ına RAW (ESC/POS) veri gönderir.

import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

String? getDefaultPrinterName() {
  final needed = calloc<Uint32>();
  // İlk çağrı: buffer boyutunu öğren
  GetDefaultPrinter(nullptr, needed);
  if (needed.value == 0) {
    calloc.free(needed);
    return null;
  }
  final name = wsalloc(needed.value);
  final ok = GetDefaultPrinter(name, needed);
  final result = ok != 0 ? name.toDartString() : null;
  calloc.free(name);
  calloc.free(needed);
  return result;
}

void writeRawToPrinterWindows(String printerName, List<int> data) {
  final pPrinterName = TEXT(printerName);
  final phPrinter = calloc<HANDLE>();

  try {
    final opened = OpenPrinter(pPrinterName, phPrinter, nullptr);
    if (opened == 0) {
      throw Exception('OpenPrinter başarısız. Hata: ${GetLastError()}');
    }
    final hPrinter = phPrinter.value;

    final docInfo = calloc<DOC_INFO_1>();
    docInfo.ref.pDocName    = TEXT('BISCORNUE Ticket');
    docInfo.ref.pOutputFile = nullptr;
    docInfo.ref.pDatatype   = TEXT('RAW'); // ESC/POS için RAW şart

    final job = StartDocPrinter(hPrinter, 1, docInfo);
    if (job == 0) { throw Exception('StartDocPrinter başarısız. Hata: ${GetLastError()}'); }

    StartPagePrinter(hPrinter);

    final pData = calloc<Uint8>(data.length);
    pData.asTypedList(data.length).setAll(0, data);
    final written = calloc<Uint32>();
    final ok = WritePrinter(hPrinter, pData, data.length, written);

    EndPagePrinter(hPrinter);
    EndDocPrinter(hPrinter);
    ClosePrinter(hPrinter);

    calloc.free(written);
    calloc.free(pData);
    calloc.free(docInfo);

    if (ok == 0) {
      throw Exception('WritePrinter başarısız. Hata: ${GetLastError()}');
    }
  } finally {
    calloc.free(pPrinterName);
    calloc.free(phPrinter);
  }
}
