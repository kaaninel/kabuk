import 'package:flutter/material.dart';

extension ContextExtension on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get text => theme.textTheme;
  ColorScheme get color => theme.colorScheme;
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  Size get screenSize => mediaQuery.size;
  double get screenWidth => screenSize.width;
  double get screenHeight => screenSize.height;
  EdgeInsets get padding => mediaQuery.padding;
  EdgeInsets get viewInsets => mediaQuery.viewInsets;
  EdgeInsets get viewPadding => mediaQuery.viewPadding;
  bool get isDarkMode => theme.brightness == Brightness.dark;
  bool get isLightMode => theme.brightness == Brightness.light;
  bool get isLandscape => mediaQuery.orientation == Orientation.landscape;
  bool get isPortrait => mediaQuery.orientation == Orientation.portrait;
  bool get isTablet => mediaQuery.size.shortestSide >= 600;
  bool get isPhone => mediaQuery.size.shortestSide < 600;
  bool get isDesktop => mediaQuery.size.shortestSide >= 1440;
  bool get isMobile => mediaQuery.size.shortestSide < 1440;
  bool get isLargeScreen => mediaQuery.size.shortestSide >= 1200;
  bool get isMediumScreen => mediaQuery.size.shortestSide >= 600;
  bool get isSmallScreen => mediaQuery.size.shortestSide < 600;
}
