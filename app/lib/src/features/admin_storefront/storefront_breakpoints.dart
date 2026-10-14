/// Layout breakpoints for the admin storefront builder (LayoutBuilder-based).
abstract final class StorefrontBreakpoints {
  static const double mobileMax = 650;
  static const double tabletMax = 1000;

  static bool isMobile(double width) => width < mobileMax;
  static bool isTablet(double width) => width >= mobileMax && width < tabletMax;
  static bool isDesktop(double width) => width >= tabletMax;
}
