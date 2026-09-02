import 'package:bike_control/pages/overview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldShowConnectionAlertToast', () {
    test('connection alert on mobile cards page (page 0) is suppressed', () {
      // Card is on screen (page 0, frontmost, narrow) and it's a connection
      // alert → the card already shows the state, so no redundant toast.
      expect(
        shouldShowConnectionAlertToast(
          screenshotMode: false,
          overviewFrontmost: true,
          screenWidth: 400,
          pageViewPage: 0,
          isConnectionAlert: true,
        ),
        isFalse,
      );
    });

    test('non-connection alert on mobile cards page still shows', () {
      expect(
        shouldShowConnectionAlertToast(
          screenshotMode: false,
          overviewFrontmost: true,
          screenWidth: 400,
          pageViewPage: 0,
          isConnectionAlert: false,
        ),
        isTrue,
      );
    });

    test('connection alert while another route is pushed still shows', () {
      // Overview is not frontmost → the card is not visible, so keep the toast.
      expect(
        shouldShowConnectionAlertToast(
          screenshotMode: false,
          overviewFrontmost: false,
          screenWidth: 400,
          pageViewPage: 0,
          isConnectionAlert: true,
        ),
        isTrue,
      );
    });

    test('desktop frontmost connection alert is suppressed', () {
      // Wide layout keeps the card permanently on screen → suppress.
      expect(
        shouldShowConnectionAlertToast(
          screenshotMode: false,
          overviewFrontmost: true,
          screenWidth: 1200,
          pageViewPage: 0,
          isConnectionAlert: true,
        ),
        isFalse,
      );
    });

    test('connection alert on mobile activity-log page (page 1) is suppressed by base', () {
      // Base show condition is already false on the activity-log page.
      expect(
        shouldShowConnectionAlertToast(
          screenshotMode: false,
          overviewFrontmost: true,
          screenWidth: 400,
          pageViewPage: 1,
          isConnectionAlert: true,
        ),
        isFalse,
      );
    });

    test('screenshot mode never shows a toast', () {
      expect(
        shouldShowConnectionAlertToast(
          screenshotMode: true,
          overviewFrontmost: false,
          screenWidth: 400,
          pageViewPage: 0,
          isConnectionAlert: false,
        ),
        isFalse,
      );
    });

    test('non-connection alert on desktop frontmost is suppressed by base', () {
      // Base condition: frontmost + wide → false regardless of alert type.
      expect(
        shouldShowConnectionAlertToast(
          screenshotMode: false,
          overviewFrontmost: true,
          screenWidth: 1200,
          pageViewPage: 0,
          isConnectionAlert: false,
        ),
        isFalse,
      );
    });
  });
}
