// Windows spooler'a RAW veri gönderme (USB/yerel yazıcı)
// Bu dosya sadece Windows'ta kullanılacak.
import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Varsayılan yazıcı adını döndürür (Windows).
String? getDefaultPrinterName() {
  if (!Platform.isWindows) return null;
  final needed = calloc<Uint32>();
  // İlk çağrıda buffer boyutunu öğren
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

/// Verilen yazıcı adına RAW (ESC/POS) bayt yazar.
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
    docInfo.ref.pDocName = TEXT('BISCORNUE Ticket');
    docInfo.ref.pOutputFile = nullptr;
    docInfo.ref.pDatatype = TEXT('RAW'); // ÖNEMLİ: ESC/POS için RAW

    final job = StartDocPrinter(hPrinter, 1, docInfo);
    if (job == 0) {
      throw Exception('StartDocPrinter başarısız. Hata: ${GetLastError()}');
    }

    StartPagePrinter(hPrinter);

    final pData = calloc<Uint8>(data.length);
    pData.asTypedList(data.length).setAll(0, data);
    final written = calloc<Uint32>();
    final ok = WritePrinter(hPrinter, pData, data.length, written);
    calloc.free(pData);

    EndPagePrinter(hPrinter);
    EndDocPrinter(hPrinter);
    ClosePrinter(hPrinter);

    calloc.free(written);
    calloc.free(docInfo);

    if (ok == 0) {
      throw Exception('WritePrinter başarısız. Hata: ${GetLastError()}');
    }
  } finally {
    calloc.free(pPrinterName);
    calloc.free(phPrinter);
  }
}
