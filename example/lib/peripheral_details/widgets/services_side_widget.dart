import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/utils.dart';
import 'services_list_widget.dart';

class ServicesSideWidget extends StatefulWidget {
  final List<BleService> discoveredServices;
  final Function(Set<CharacteristicProperty>? selectedProperties,
      GlobalKey<ServicesListWidgetState>? listKey, bool isDiscoveringServices)
      serviceListBuilder;
  final VoidCallback? onCopyServices;
  final BleService? selectedService;
  final BleCharacteristic? selectedCharacteristic;
  final Function(BleService service, BleCharacteristic characteristic)?
      onCharacteristicSelected;
  final Function(Set<CharacteristicProperty>? propertyFilters)?
      onPropertyFiltersChanged;
  final Set<CharacteristicProperty>? initialPropertyFilters;
  final bool isDiscoveringServices;
  const ServicesSideWidget({
    super.key,
    required this.discoveredServices,
    required this.serviceListBuilder,
    this.onCopyServices,
    this.selectedService,
    this.selectedCharacteristic,
    this.onCharacteristicSelected,
    this.onPropertyFiltersChanged,
    this.initialPropertyFilters,
    this.isDiscoveringServices = false,
  });

  @override
  State<ServicesSideWidget> createState() => _ServicesSideWidgetState();
}

class _ServicesSideWidgetState extends State<ServicesSideWidget> {
  late Set<CharacteristicProperty>? _selectedProperties;
  bool _showFilters = false;
  final GlobalKey<ServicesListWidgetState> _servicesListKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectedProperties = widget.initialPropertyFilters != null
        ? Set<CharacteristicProperty>.from(widget.initialPropertyFilters!)
        : null;
  }

  @override
  void didUpdateWidget(ServicesSideWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update filters if initial filters changed from outside
    final newFilters = widget.initialPropertyFilters;
    final oldFilters = oldWidget.initialPropertyFilters;
    if (newFilters != oldFilters) {
      setState(() {
        _selectedProperties = newFilters != null
            ? Set<CharacteristicProperty>.from(newFilters)
            : null;
      });
    }
  }

  void _togglePropertyFilter(CharacteristicProperty property) {
    setState(() {
      _selectedProperties ??= <CharacteristicProperty>{};
      if (_selectedProperties!.contains(property)) {
        _selectedProperties!.remove(property);
        if (_selectedProperties!.isEmpty) {
          _selectedProperties = null;
        }
      } else {
        _selectedProperties!.add(property);
      }
    });
    widget.onPropertyFiltersChanged?.call(_selectedProperties);
  }

  void _clearFilters() {
    setState(() {
      _selectedProperties = null;
    });
    widget.onPropertyFiltersChanged?.call(null);
  }

  void _navigateToAdjacent(bool forward) {
    final listState = _servicesListKey.currentState;
    if (listState == null || widget.selectedCharacteristic == null) return;

    final filtered = listState.getFilteredCharacteristics();
    final result = navigateToAdjacentCharacteristic(
      filtered,
      widget.selectedCharacteristic!.uuid,
      forward,
    );

    if (result != null) {
      widget.onCharacteristicSelected?.call(
        result.service,
        result.characteristic,
      );
    }
  }

  void _navigateToPrevious() {
    _navigateToAdjacent(false);
  }

  void _navigateToNext() {
    _navigateToAdjacent(true);
  }

  bool _canNavigate() {
    final listState = _servicesListKey.currentState;
    if (listState == null) return false;
    final filtered = listState.getFilteredCharacteristics();
    return filtered.length > 1;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasActiveFilters =
        _selectedProperties != null && _selectedProperties!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          right: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.apps,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Services',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    // Navigation buttons
                    if (_canNavigate()) ...[
                      IconButton(
                        onPressed: _navigateToPrevious,
                        icon: const Icon(Icons.arrow_back_ios),
                        iconSize: 18,
                        tooltip: 'Previous Characteristic',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        color: colorScheme.primary,
                      ),
                      IconButton(
                        onPressed: _navigateToNext,
                        icon: const Icon(Icons.arrow_forward_ios),
                        iconSize: 18,
                        tooltip: 'Next Characteristic',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _showFilters = !_showFilters;
                        });
                      },
                      icon: Icon(
                        Icons.filter_list,
                        color: hasActiveFilters
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                      iconSize: 18,
                      tooltip: 'Filter by Properties',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                    if (widget.onCopyServices != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: IconButton(
                          onPressed: widget.onCopyServices,
                          icon: const Icon(Icons.copy),
                          iconSize: 18,
                          tooltip: 'Copy Services',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          color: colorScheme.onSurface,
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${widget.discoveredServices.length}',
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_showFilters) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Filter by Properties',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            if (hasActiveFilters)
                              TextButton(
                                onPressed: _clearFilters,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Clear',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children:
                              CharacteristicProperty.values.map((property) {
                            final isSelected =
                                _selectedProperties?.contains(property) ??
                                    false;
                            return FilterChip(
                              label: Text(
                                property.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              selected: isSelected,
                              onSelected: (_) =>
                                  _togglePropertyFilter(property),
                              selectedColor: colorScheme.primaryContainer,
                              checkmarkColor: colorScheme.onPrimaryContainer,
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurface,
                              ),
                              side: BorderSide(
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.outline
                                        .withValues(alpha: 0.3),
                                width: isSelected ? 1.5 : 1,
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: widget.discoveredServices.isEmpty
                ? Center(
                    child: widget.isDiscoveringServices
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                color: colorScheme.primary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Discovering services...',
                                style: TextStyle(
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.apps_outlined,
                                size: 48,
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No Services Discovered',
                                style: TextStyle(
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                  )
                : widget.serviceListBuilder(
                    _selectedProperties, _servicesListKey, widget.isDiscoveringServices),
          ),
        ],
      ),
    );
  }
}
