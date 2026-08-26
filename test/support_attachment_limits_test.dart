import 'package:bike_control/services/support_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SupportAttachmentLimits', () {
    test('maps every pickable extension to an allowed MIME type', () {
      // Mirrors the composer's allowedExtensions list — a pickable file the
      // service can't map (or maps outside the allowlist) fails only at
      // upload, after the user already chose it.
      const pickable = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'pdf', 'txt', 'log', 'zip'];
      for (final ext in pickable) {
        final mime = SupportAttachmentLimits.mimeTypeForName('file.$ext');
        expect(mime, isNotNull, reason: '.$ext must map to a MIME type');
        expect(
          SupportAttachmentLimits.allowedMimeTypes,
          contains(mime),
          reason: '.$ext maps to $mime, which must be allowed',
        );
      }
    });

    test('log files upload as plain text, archives as zip', () {
      expect(SupportAttachmentLimits.mimeTypeForName('rouvy.log'), 'text/plain');
      expect(SupportAttachmentLimits.mimeTypeForName('ROUVY.ZIP'), 'application/zip');
    });

    test('unknown extensions stay rejected', () {
      expect(SupportAttachmentLimits.mimeTypeForName('setup.exe'), isNull);
      expect(SupportAttachmentLimits.mimeTypeForName('noextension'), isNull);
    });
  });
}
