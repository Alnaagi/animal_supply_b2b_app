import 'package:flutter/material.dart';

import '../admin_storefront_controller.dart';

Future<void> showStorefrontPreviewSettingsSheet({
  required BuildContext context,
  required StorefrontBuilderState state,
  required AdminStorefrontController controller,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: _PreviewSettingsBody(
            state: state,
            controller: controller,
          ),
        ),
      );
    },
  );
}

class _PreviewSettingsBody extends StatelessWidget {
  const _PreviewSettingsBody({
    required this.state,
    required this.controller,
  });

  final StorefrontBuilderState state;
  final AdminStorefrontController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('storefront-preview-settings-sheet'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'إعدادات المعاينة',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Text(
            'الجهاز',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<StorefrontPreviewDevice>(
            key: const Key('storefront-preview-settings-device-segments'),
            segments: [
              for (final device in StorefrontPreviewDevice.values)
                ButtonSegment(
                  value: device,
                  label: Text(device.labelAr),
                ),
            ],
            selected: {state.previewDevice},
            onSelectionChanged: (value) =>
                controller.setPreviewDevice(value.first),
          ),
          const SizedBox(height: 16),
          Text(
            'نسخة التصميم',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('المسودة')),
              ButtonSegment(value: true, label: Text('المنشور')),
            ],
            selected: {state.previewPublished},
            onSelectionChanged: (value) =>
                controller.togglePreviewPublished(value.first),
          ),
          const SizedBox(height: 16),
          Text(
            'الأسعار',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<StorefrontPricePreviewMode>(
            segments: [
              for (final mode in StorefrontPricePreviewMode.values)
                ButtonSegment(
                  value: mode,
                  label: Text(mode.labelAr),
                ),
            ],
            selected: {state.pricePreviewMode},
            onSelectionChanged: (value) =>
                controller.setPricePreviewMode(value.first),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
