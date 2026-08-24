// "Guides & blog" section body (Task 10) — the blog half of the "Guides &
// videos" card. `BlogPostsWidget` already does everything this needs
// (loading skeleton, "NEW" badge, 5-most-recent default, tap-to-open), so
// this is a thin composition that just suppresses its own header — the
// section card above already titles itself "Guides & videos" — rather than
// re-implementing the row UI.
import 'package:bike_control/services/blog_service.dart';
import 'package:bike_control/widgets/blog_posts_widget.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class BlogSection extends StatelessWidget {
  /// Test seam: replaces the default `BlogService().fetchPosts()` call
  /// threaded through to [BlogPostsWidget] — see
  /// help_center_sections_test.dart.
  final Future<List<BlogPost>>? postsFuture;

  const BlogSection({super.key, this.postsFuture});

  @override
  Widget build(BuildContext context) {
    return BlogPostsWidget(showHeader: false, postsFutureOverride: postsFuture);
  }
}
