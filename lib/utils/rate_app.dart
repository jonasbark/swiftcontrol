import 'package:in_app_review/in_app_review.dart';

/// Requests an in-app store rating prompt, falling back to opening the store
/// listing directly when the native review sheet isn't available (e.g. the
/// per-account/OS quota for in-app prompts was already used up).
Future<void> requestAppRating() async {
  final review = InAppReview.instance;
  if (await review.isAvailable()) {
    await review.requestReview();
  } else {
    await review.openStoreListing(appStoreId: 'id6753721284', microsoftStoreId: '9NP42GS03Z26');
  }
}
