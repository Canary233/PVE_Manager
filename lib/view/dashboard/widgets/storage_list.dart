import 'package:flutter/material.dart';

import 'package:pve_manager/core/l10n/l10n_extensions.dart';
import 'package:pve_manager/data/models/pve_resource.dart';
import 'package:pve_manager/core/utils/formatters.dart';
import 'package:pve_manager/core/widgets/empty_state.dart';
import 'package:pve_manager/core/widgets/usage_line.dart';

class StorageList extends StatelessWidget {
  const StorageList({
    required this.storages,
    required this.permissionDenied,
    this.onStorageTap,
    this.selectedStorageId,
    super.key,
  });

  final List<PveResource> storages;
  final bool permissionDenied;
  final ValueChanged<PveResource>? onStorageTap;
  final String? selectedStorageId;

  @override
  Widget build(BuildContext context) {
    if (permissionDenied) {
      return EmptyState(text: context.l10n.noPermission);
    }

    if (storages.isEmpty) {
      return EmptyState(text: context.l10n.noStorage);
    }

    return Card(
      color: Theme.of(context).colorScheme.surface,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: storages.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final storage = storages[index];
          final selected = storage.id == selectedStorageId;
          final colorScheme = Theme.of(context).colorScheme;
          return InkWell(
            onTap: onStorageTap == null ? null : () => onStorageTap!(storage),
            child: ColoredBox(
              color: selected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.42)
                  : Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storage_rounded),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            storage.name,
                            style: Theme.of(context).textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(storage.node),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    UsageLine(
                      label: context.l10n.capacity,
                      value: storage.diskRatio,
                      text:
                          '${bytes(storage.diskUsed)} / ${bytes(storage.diskTotal)}',
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
