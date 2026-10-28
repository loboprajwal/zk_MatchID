import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xfff1efe8);
  static const surface = Color(0xffffffff);
  static const surfaceMuted = Color(0xfff7f7f5);
  static const primary = Color(0xff26215c);
  static const text = Color(0xff222222);
  static const secondaryText = Color(0xff777777);
  static const border = Color(0xffeeeeec);
  static const chip = Color(0xffeeedfe);
  static const validBackground = Color(0xffeaf3de);
  static const validText = Color(0xff27500a);
  static const pendingBackground = Color(0xfffaeeda);
  static const pendingText = Color(0xff633806);
  static const danger = Color(0xff791f1f);
  static const dangerBackground = Color(0xfffcebeb);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
}

abstract final class AppRadius {
  static const small = 8.0;
  static const button = 9.0;
  static const card = 11.0;
  static const large = 20.0;
  static const phone = 30.0;
}

abstract final class AppShadows {
  static const card = [
    BoxShadow(color: Color(0x26000000), blurRadius: 10, offset: Offset(0, 4)),
  ];
}

abstract final class AppTypography {
  static const family = 'Roboto';
  static const sectionTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );
  static const bodySmall = TextStyle(
    fontSize: 11,
    color: AppColors.secondaryText,
  );
}

@immutable
class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({
    required this.border,
    required this.mutedSurface,
    required this.cardRadius,
    required this.contentPadding,
  });

  final Color border;
  final Color mutedSurface;
  final double cardRadius;
  final double contentPadding;

  static const light = AppThemeTokens(
    border: AppColors.border,
    mutedSurface: AppColors.surfaceMuted,
    cardRadius: AppRadius.card,
    contentPadding: AppSpacing.md,
  );

  @override
  AppThemeTokens copyWith({
    Color? border,
    Color? mutedSurface,
    double? cardRadius,
    double? contentPadding,
  }) =>
      AppThemeTokens(
        border: border ?? this.border,
        mutedSurface: mutedSurface ?? this.mutedSurface,
        cardRadius: cardRadius ?? this.cardRadius,
        contentPadding: contentPadding ?? this.contentPadding,
      );

  @override
  AppThemeTokens lerp(ThemeExtension<AppThemeTokens>? other, double t) {
    if (other is! AppThemeTokens) return this;
    return AppThemeTokens(
      border: Color.lerp(border, other.border, t) ?? border,
      mutedSurface:
          Color.lerp(mutedSurface, other.mutedSurface, t) ?? mutedSurface,
      cardRadius: cardRadius + (other.cardRadius - cardRadius) * t,
      contentPadding:
          contentPadding + (other.contentPadding - contentPadding) * t,
    );
  }
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: AppColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: const [AppThemeTokens.light],
    scaffoldBackgroundColor: AppColors.background,
    textTheme: ThemeData.light().textTheme.apply(
          bodyColor: AppColors.text,
          displayColor: AppColors.text,
          fontFamily: AppTypography.family,
        ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceMuted,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        fontFamily: AppTypography.family,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.all(AppSpacing.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.small),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.small),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.small),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: Color(0xffcccccc)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.chip,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 10,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.secondaryText,
          )),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.chip,
      selectedColor: AppColors.chip,
      disabledColor: AppColors.surfaceMuted,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      labelStyle: const TextStyle(
        color: AppColors.primary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? AppColors.surface
              : AppColors.secondaryText),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.border),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      titleTextStyle: const TextStyle(
        color: AppColors.text,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        fontFamily: AppTypography.family,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
  );
}
