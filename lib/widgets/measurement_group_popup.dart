import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/soil_measurement.dart';
import '../utils/measurement_map_utils.dart';

class MeasurementGroupMarkerLabel extends StatelessWidget {
  const MeasurementGroupMarkerLabel({
    super.key,
    required this.group,
    required this.onMarkerTap,
  });

  final MeasurementMapGroup group;
  final ValueChanged<BuildContext> onMarkerTap;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (labelContext) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onMarkerTap(labelContext),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 108),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 2),
              ],
            ),
            child: Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(Icons.location_on, color: Colors.green, size: 30),
        ],
      ),
    ),
  );
}

void showMeasurementGroupPopup({
  required BuildContext context,
  required BuildContext anchorContext,
  required MeasurementMapGroup group,
}) {
  final anchorBox = anchorContext.findRenderObject() as RenderBox?;
  if (anchorBox == null || !anchorBox.attached) return;
  final overlayBox =
      Overlay.of(context, rootOverlay: true).context.findRenderObject()
          as RenderBox;
  final anchorRect = Rect.fromPoints(
    anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox),
    anchorBox.localToGlobal(
      anchorBox.size.bottomRight(Offset.zero),
      ancestor: overlayBox,
    ),
  );
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black26,
    useSafeArea: true,
    builder: (dialogContext) => LayoutBuilder(
      builder: (context, constraints) {
        const margin = 12.0;
        final width = math.min(360.0, constraints.maxWidth - margin * 2);
        final height = math.min(420.0, constraints.maxHeight - margin * 2);
        final left = (anchorRect.center.dx - width / 2)
            .clamp(margin, constraints.maxWidth - width - margin)
            .toDouble();
        final below = anchorRect.bottom + 8;
        final top =
            (below + height <= constraints.maxHeight - margin
                    ? below
                    : anchorRect.top - height - 8)
                .clamp(margin, constraints.maxHeight - height - margin)
                .toDouble();
        return Stack(
          children: [
            Positioned.fill(
              child: const ModalBarrier(
                dismissible: false,
                color: Colors.transparent,
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: _MeasurementGroupPopup(
                group: group,
                onDismiss: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _MeasurementGroupPopup extends StatefulWidget {
  const _MeasurementGroupPopup({required this.group, required this.onDismiss});
  final MeasurementMapGroup group;
  final VoidCallback onDismiss;
  @override
  State<_MeasurementGroupPopup> createState() => _MeasurementGroupPopupState();
}

class _MeasurementGroupPopupState extends State<_MeasurementGroupPopup> {
  SoilMeasurement? _selected;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Card(
      margin: EdgeInsets.zero,
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_selected != null)
                  IconButton(
                    tooltip: 'Back to measurement times',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() => _selected = null),
                  ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: widget.onDismiss,
                ),
              ],
            ),
            if (_selected == null)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Text('เลือกวันที่และเวลาที่วัด'),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: widget.group.measurements.length,
                        itemBuilder: (_, index) {
                          final record = widget.group.measurements[index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.schedule_rounded),
                            title: Text(_timestamp(record.timestamp)),
                            onTap: () => setState(() => _selected = record),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: _MeasurementDetails(measurement: _selected!),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

String _timestamp(DateTime time) =>
    '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year} '
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

class _MeasurementDetails extends StatelessWidget {
  const _MeasurementDetails({required this.measurement});
  final SoilMeasurement measurement;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'บันทึกเมื่อ: ${_timestamp(measurement.timestamp)}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      _row('อุณหภูมิ', '${measurement.temperature.toStringAsFixed(2)} °C'),
      _row('ความชื้น', '${measurement.moisture.toStringAsFixed(1)} %'),
      _row('EC', '${measurement.ec.toStringAsFixed(0)} µS/cm'),
      _row('ความเค็ม', '${measurement.salinity.toStringAsFixed(0)} mg/L'),
      _row('ไนโตรเจน', '${measurement.nitrogen.toStringAsFixed(0)} mg/kg'),
      _row('ฟอสฟอรัส', '${measurement.phosphorus.toStringAsFixed(0)} mg/kg'),
      _row('โพแทสเซียม', '${measurement.potassium.toStringAsFixed(0)} mg/kg'),
      _row('pH', measurement.ph.toStringAsFixed(2)),
    ],
  );
  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
