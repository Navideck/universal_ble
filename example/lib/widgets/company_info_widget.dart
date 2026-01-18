import 'package:flutter/material.dart';
import 'package:universal_ble_example/data/company_identifier_service.dart';

/// A reusable widget that displays company information for a given company ID.
/// 
/// This widget fetches the company name from the CompanyIdentifierService
/// and displays it in a consistent format. If no company name is found,
/// the widget returns an empty SizedBox.
class CompanyInfoWidget extends StatelessWidget {
  /// The company ID to look up
  final int companyId;
  
  /// Optional text style for the "Company:" label
  final TextStyle? labelStyle;
  
  /// Optional text style for the company name
  final TextStyle? nameStyle;
  
  /// Optional padding around the widget
  final EdgeInsets? padding;
  
  /// Optional color scheme. If not provided, will be obtained from Theme
  final ColorScheme? colorScheme;

  const CompanyInfoWidget({
    super.key,
    required this.companyId,
    this.labelStyle,
    this.nameStyle,
    this.padding,
    this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final companyName = CompanyIdentifierService.instance.getCompanyName(companyId);
    
    if (companyName == null) {
      return const SizedBox.shrink();
    }

    final effectiveColorScheme = colorScheme ?? Theme.of(context).colorScheme;
    final effectiveLabelStyle = labelStyle ??
        TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: effectiveColorScheme.onSecondaryContainer,
        );
    final effectiveNameStyle = nameStyle ??
        TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: effectiveColorScheme.onSecondaryContainer,
        );
    final effectivePadding = padding ?? const EdgeInsets.only(top: 4);

    return Padding(
      padding: effectivePadding,
      child: Row(
        children: [
          Text(
            'Company: ',
            style: effectiveLabelStyle,
          ),
          Expanded(
            child: SelectableText(
              companyName,
              style: effectiveNameStyle,
            ),
          ),
        ],
      ),
    );
  }
}
