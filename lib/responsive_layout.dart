part of 'main.dart';

/// Shared layout rules used by portrait pages and the route-scoped landscape
/// experience. Keeping these values in one place prevents each screen from
/// making a different assumption about phone width.
abstract final class AppLayout {
  static const double phoneContentMaxWidth = 560;
  static const double homeContentMaxWidth = 720;
  static const double dialogContentMaxWidth = 520;

  static bool isCompactWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 360;

  static bool isShortHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height < 650;

  static double pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 340) return 12;
    if (width < 400) return 16;
    return 20;
  }

  static double footerPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 340) return 12;
    if (width < 400) return 18;
    return 24;
  }
}

class AppConstrainedContent extends StatelessWidget {
  const AppConstrainedContent({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.phoneContentMaxWidth,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

/// Scales labels down only when a compact control cannot fit them. It avoids
/// hard clipping while leaving normal-sized phones and accessibility text
/// scaling untouched everywhere else.
class AppButtonLabel extends StatelessWidget {
  const AppButtonLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(label, maxLines: 1, textAlign: TextAlign.center),
  );
}
