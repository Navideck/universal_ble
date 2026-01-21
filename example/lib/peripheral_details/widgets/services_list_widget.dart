import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:universal_ble_example/data/utils.dart';

class ServicesListWidget extends StatefulWidget {
  final List<BleService> discoveredServices;
  final bool scrollable;
  final void Function(BleService service, BleCharacteristic characteristic)?
      onTap;
  final BleService? selectedService;
  final BleCharacteristic? selectedCharacteristic;
  final Set<String>? favoriteServices;
  final Map<String, bool>? subscribedCharacteristics;
  final void Function(String serviceUuid)? onFavoriteToggle;
  final Set<CharacteristicProperty>? propertyFilters;
  final bool isDiscoveringServices;

  const ServicesListWidget({
    super.key,
    required this.discoveredServices,
    this.onTap,
    this.scrollable = false,
    this.selectedService,
    this.selectedCharacteristic,
    this.favoriteServices,
    this.subscribedCharacteristics,
    this.onFavoriteToggle,
    this.propertyFilters,
    this.isDiscoveringServices = false,
  });

  @override
  State<ServicesListWidget> createState() => ServicesListWidgetState();
}

class ServicesListWidgetState extends State<ServicesListWidget> {
  final Map<String, ExpansibleController> _expandableControllers = {};
  ScrollController? _scrollController;
  final Map<String, GlobalKey> _characteristicKeys = {};

  @override
  void initState() {
    super.initState();
    if (widget.scrollable) {
      _scrollController = ScrollController();
    }
    _initializeControllers();
    // Scroll to selected characteristic after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedCharacteristic();
    });
  }

  @override
  void didUpdateWidget(ServicesListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Create or dispose scroll controller if scrollable state changed
    if (oldWidget.scrollable != widget.scrollable) {
      if (widget.scrollable && _scrollController == null) {
        _scrollController = ScrollController();
      } else if (!widget.scrollable && _scrollController != null) {
        _scrollController!.dispose();
        _scrollController = null;
      }
    }
    // Update controllers if services or selection changed
    if (oldWidget.discoveredServices != widget.discoveredServices ||
        oldWidget.selectedCharacteristic != widget.selectedCharacteristic) {
      _initializeControllers();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelectedCharacteristic();
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _expandableControllers.values) {
      controller.dispose();
    }
    _scrollController?.dispose();
    super.dispose();
  }

  void _initializeControllers() {
    // Dispose old controllers
    for (var controller in _expandableControllers.values) {
      controller.dispose();
    }
    _expandableControllers.clear();
    _characteristicKeys.clear();

    // Create controllers for each service
    final sortedServices = _getSortedServices();
    for (var service in sortedServices) {
      final controller = ExpansibleController();
      // Expand if this service contains the selected characteristic
      if (widget.selectedCharacteristic != null) {
        final hasSelectedChar = service.characteristics.any(
          (char) => char.uuid == widget.selectedCharacteristic!.uuid,
        );
        if (hasSelectedChar) {
          controller.expand();
        }
      }
      _expandableControllers[service.uuid] = controller;

      // Create keys for characteristics
      for (var char in service.characteristics) {
        _characteristicKeys['${service.uuid}_${char.uuid}'] = GlobalKey();
      }
    }
  }

  void _scrollToSelectedCharacteristic() {
    if (widget.selectedCharacteristic == null) return;

    // Find the key for the selected characteristic
    String? selectedKey;

    // Prefer an exact match on both service and characteristic UUIDs
    if (widget.selectedService != null) {
      final exactKey =
          '${widget.selectedService!.uuid}_${widget.selectedCharacteristic!.uuid}';
      if (_characteristicKeys.containsKey(exactKey)) {
        selectedKey = exactKey;
      }
    }

    // Fallback: match by characteristic UUID only if no exact key was found
    if (selectedKey == null) {
      for (var entry in _characteristicKeys.entries) {
        if (entry.key.endsWith('_${widget.selectedCharacteristic!.uuid}')) {
          selectedKey = entry.key;
          break;
        }
      }
    }
    if (selectedKey != null) {
      final key = _characteristicKeys[selectedKey];
      if (key?.currentContext != null) {
        // Wait a bit for the expansion animation to complete
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && key?.currentContext != null) {
            Scrollable.ensureVisible(
              key!.currentContext!,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        });
      }
    }
  }

  List<BleService> _getSortedServices() {
    return sortBleServices(
      widget.discoveredServices,
      favoriteServices: widget.favoriteServices,
    );
  }

  /// Returns a list of all filtered characteristics with their parent services
  List<({BleService service, BleCharacteristic characteristic})>
      getFilteredCharacteristics() {
    return getFilteredBleCharacteristics(
      widget.discoveredServices,
      favoriteServices: widget.favoriteServices,
      propertyFilters: widget.propertyFilters,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final favoriteStarColor = Colors.amber;
    final subscribedNotificationIconColor = Colors.green;
    final selectedColor = colorScheme.primary;
    final selectedCharacteristicBackgroundColor =
        colorScheme.primaryContainer.withValues(alpha: 0.5);

    final sortedServices = _getSortedServices();

    // Show loading indicator when discovering services and list is empty
    if (widget.isDiscoveringServices && sortedServices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Discovering services...',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Show loading overlay when re-discovering services (list has items)
    if (widget.isDiscoveringServices && sortedServices.isNotEmpty) {
      return Stack(
        children: [
          _buildServicesListView(
              sortedServices,
              colorScheme,
              favoriteStarColor,
              subscribedNotificationIconColor,
              selectedColor,
              selectedCharacteristicBackgroundColor),
          Positioned.fill(
            child: Container(
              color: colorScheme.surface.withValues(alpha: 0.7),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Discovering services...',
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Normal list view when not loading
    return _buildServicesListView(
        sortedServices,
        colorScheme,
        favoriteStarColor,
        subscribedNotificationIconColor,
        selectedColor,
        selectedCharacteristicBackgroundColor);
  }

  Widget _buildServicesListView(
    List<BleService> sortedServices,
    ColorScheme colorScheme,
    Color favoriteStarColor,
    Color subscribedNotificationIconColor,
    Color selectedColor,
    Color selectedCharacteristicBackgroundColor,
  ) {
    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: !widget.scrollable,
      physics: widget.scrollable ? null : const NeverScrollableScrollPhysics(),
      itemCount: sortedServices.length,
      itemBuilder: (BuildContext context, int index) {
        final service = sortedServices[index];
        final isFavorite =
            widget.favoriteServices?.contains(service.uuid) ?? false;
        final isSelected = widget.selectedService?.uuid == service.uuid;
        final controller =
            _expandableControllers[service.uuid] ?? ExpansibleController();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Card(
            elevation: isSelected ? 2 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isSelected
                  ? BorderSide(color: selectedColor, width: 2)
                  : BorderSide.none,
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                dividerColor: Colors.transparent,
              ),
              child: ExpansionTile(
                controller: controller,
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 0),
                shape: const Border(),
                collapsedShape: const Border(),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        service.uuid,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          color: colorScheme.onSurface,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.onFavoriteToggle != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          isFavorite ? Icons.star : Icons.star_border,
                          color: isFavorite
                              ? favoriteStarColor
                              : colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        onPressed: () => widget.onFavoriteToggle!(service.uuid),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        hoverColor: Colors.transparent,
                      ),
                    ],
                  ],
                ),
                childrenPadding: const EdgeInsets.only(bottom: 8.0),
                children: service.characteristics.where((e) {
                  // Filter by properties if filters are selected
                  if (widget.propertyFilters != null &&
                      widget.propertyFilters!.isNotEmpty) {
                    return e.properties
                        .any((prop) => widget.propertyFilters!.contains(prop));
                  }
                  return true;
                }).map((e) {
                  final isCharSelected =
                      widget.selectedCharacteristic?.uuid == e.uuid;
                  final isSubscribed =
                      widget.subscribedCharacteristics?[e.uuid] ?? false;
                  final charKey =
                      _characteristicKeys['${service.uuid}_${e.uuid}'];
                  return Padding(
                    key: charKey,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 4.0,
                    ),
                    child: GestureDetector(
                      onTap: () {
                        widget.onTap?.call(service, e);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isCharSelected
                              ? selectedCharacteristicBackgroundColor
                              : colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: isCharSelected
                              ? Border.all(color: selectedColor, width: 1.5)
                              : null,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.arrow_right_outlined,
                                    size: 16,
                                    color: isCharSelected
                                        ? selectedColor
                                        : colorScheme.onSurface
                                            .withValues(alpha: 0.6),
                                  ),
                                  const SizedBox(width: 8),
                                  if (isSubscribed) ...[
                                    Icon(
                                      Icons.notifications_active,
                                      color: subscribedNotificationIconColor,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(
                                      e.uuid,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        fontWeight: isCharSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isCharSelected
                                            ? selectedColor
                                            : colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: e.properties.map((prop) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      prop.name,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: colorScheme.onSecondaryContainer,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}
