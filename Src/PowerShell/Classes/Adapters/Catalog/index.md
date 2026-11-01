# Adapter catalog

This is a reading guide to [index.json](./index.json). The JSON file is the catalog manifest; the linked files below hold the adapter and condenser inventories. Descriptions summarize declared activities and do not imply that every activity is implemented.

## Choosing an owner, activity and property

`whenToUse` is authoring guidance in the catalog, not a property to copy into a runtime plan. Read it in three locations:

- **Owner:** on a root `mappedAdapters` entry (including the inline template) or a root `condensers` entry, to choose the owner and follow its `file` link when present. Choose PlanCondenser directly from `condensers`.
- **Activity:** on an activity object in the owning catalog, to choose an operation and recognize reserved or unimplemented activities.
- **Property:** on an activity `properties` object, to decide when that contextual input is needed or should be omitted.

The manifest retains data-format `version: 1`; `layoutVersion: 2` identifies the direct root condenser navigation. Root `condensers` is the plan-writer navigation authority. The nested `MappedCondenserAdapter.concreteAdapters` references retain structural grouping and must have the same unique names, order and resolved catalog targets; owner guidance is not duplicated there.

Guidance is being added by owner; its absence does not imply support or applicability. Empty owners remain empty. Consult the declared activity and current source when guidance is absent.

## Mapped adapters

The root manifest also contains `MappedAdapterTemplate` inline, with no activities or concrete adapters.

| Catalog file | Description |
| --- | --- |
| [MappedCondenserAdapter](./Mapped/MappedCondenserAdapter.json) | Groups the 13 concrete condenser catalogs listed below; it declares no activities at the mapped level. |
| [MappedConductionAdapter](./Mapped/MappedConductionAdapter.json) | Conduction plan invocation and execution through SovereignTrust and SDA adapters. |
| [MappedConduitAdapter](./Mapped/MappedConduitAdapter.json) | Empty mapped group; no activities or concrete adapters are declared. |
| [MappedDataAdapter](./Mapped/MappedDataAdapter.json) | Data write, query, delete, administration, and artifact process activities. |
| [MappedIntelligenceAdapter](./Mapped/MappedIntelligenceAdapter.json) | Message sending and handling through intelligence services. |
| [MappedNetworkAdapter](./Mapped/MappedNetworkAdapter.json) | File and message sending, batch reading, and message handling through a network service. |
| [MappedQuantumAdapter](./Mapped/MappedQuantumAdapter.json) | Empty mapped group; no activities or concrete adapters are declared. |
| [MappedQueueAdapter](./Mapped/MappedQueueAdapter.json) | Queue reading, writing, acknowledgement, deferral, and message handling. |
| [MappedSatelliteAdapter](./Mapped/MappedSatelliteAdapter.json) | Telemetry entry, signal, and message emission. |
| [MappedSessionAdapter](./Mapped/MappedSessionAdapter.json) | Session lookup or registration. |
| [MappedStorageAdapter](./Mapped/MappedStorageAdapter.json) | Resource read, write, delete, and existence checks across storage providers. |
| [MappedTokenAdapter](./Mapped/MappedTokenAdapter.json) | Token value resolution from a path across token providers. |
| [MappedUtilityAdapter](./Mapped/MappedUtilityAdapter.json) | Image resizing and overlay operations. |

## Condensers

Choose these owners directly from `condensers` in [index.json](./index.json). [MappedCondenserAdapter](./Mapped/MappedCondenserAdapter.json) retains their structural grouping.

| Catalog file | Description |
| --- | --- |
| [ConductionCondenser](./Condensers/ConductionCondenser.json) | SovereignTrust conduction plan invocation. |
| [ConduitCondenser](./Condensers/ConduitCondenser.json) | Plan processing through a conduit and phase graph construction. |
| [FabCondenser](./Condensers/FabCondenser.json) | Fabrication condenser invocation. |
| [FormatCondenser](./Condensers/FormatCondenser.json) | JSON, JSON array, XML, and text formatting. |
| [GraphCondenser](./Condensers/GraphCondenser.json) | Graph condenser catalog with no declared activities. |
| [HydrationCondenser](./Condensers/HydrationCondenser.json) | Hydration condenser invocation. |
| [MapCondenser](./Condensers/MapCondenser.json) | Mapping values and invoking mapping operations. |
| [MemoryCondenser](./Condensers/MemoryCondenser.json) | Memory content generation and a reserved persistence activity. |
| [MergeCondenser](./Condensers/MergeCondenser.json) | Merging signal data. |
| [PlanCondenser](./Condensers/PlanCondenser.json) | Plan and phase iteration, invocation, status, stopping, and step insertion. |
| [RestCondenser](./Condensers/RestCondenser.json) | REST method activities for GET, HEAD, POST, PUT, PATCH, DELETE, and OPTIONS. |
| [TokenCondenser](./Condensers/TokenCondenser.json) | Parsing and resolving a token. |
| [TransformCondenser](./Condensers/TransformCondenser.json) | Signal projection, selection, injection, registration, cloning, and merging. |

## Keeping the catalog in sync

- **Add or remove a mapped adapter:** change the entries in [index.json](./index.json) and the matching [mapped catalog](./Mapped/); update the mapped table above. For a condenser, reconcile the root `condensers` entries in [index.json](./index.json) with the nested references in [MappedCondenserAdapter](./Mapped/MappedCondenserAdapter.json), preserving equal ordered names and resolved targets; update the matching [condenser catalog](./Condensers/) and condenser table above.
- **Change a declared activity or input:** update its owning catalog file under [Mapped](./Mapped/) or [Condensers](./Condensers/), including affected `properties`, adapter-specific `default`, and `whenToUse` guidance. Update the [attribution matrix](../../../../../Documentation/Projects/Working/Adapter-Index-Attribution-Matrix.json) and its [owner shard](../../../../../Documentation/Projects/Working/Adapter-Index-Attribution-Matrix/) when the source-backed inventory, attribution, or source identity changes. Revise a table description here only if its summary changes.
- **Change an observable result:** update the owning catalog's activity `result` and its linked companion under [ResultContracts](../ResultContracts/) when the result contract or its evidence changes. Check affected result consumers and tests.
- **Change implementation or dispatch:** reconcile the affected catalog declarations, matrix evidence, result companion, and [adapter tests](../../../../../Tests/) according to what changed; an implementation edit alone does not require rewriting every document. The matrix is retained source-attribution evidence. The [activity-properties plan](../../../../../Documentation/Projects/Working/Adapter-Index-Activity-Properties-Plan.md) records historical decisions, while the manifest and catalog files above hold the current inventory.
