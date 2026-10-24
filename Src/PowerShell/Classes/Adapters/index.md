# Adapter catalog

This is a reading guide to [index.json](./index.json). The JSON file is the catalog manifest; the linked files below hold the adapter and condenser inventories. Descriptions summarize declared activities and do not imply that every activity is implemented.

## Mapped adapters

The root manifest also contains `MappedAdapterTemplate` inline, with no activities or concrete adapters.

| Catalog file | Description |
| --- | --- |
| [MappedCondenserAdapter](./Catalog/Mapped/MappedCondenserAdapter.json) | Groups the 13 concrete condenser catalogs listed below; it declares no activities at the mapped level. |
| [MappedConductionAdapter](./Catalog/Mapped/MappedConductionAdapter.json) | Conduction plan invocation and execution through SovereignTrust and SDA adapters. |
| [MappedConduitAdapter](./Catalog/Mapped/MappedConduitAdapter.json) | Empty mapped group; no activities or concrete adapters are declared. |
| [MappedDataAdapter](./Catalog/Mapped/MappedDataAdapter.json) | Data write, query, delete, administration, and artifact process activities. |
| [MappedIntelligenceAdapter](./Catalog/Mapped/MappedIntelligenceAdapter.json) | Message sending and handling through intelligence services. |
| [MappedNetworkAdapter](./Catalog/Mapped/MappedNetworkAdapter.json) | File and message sending, batch reading, and message handling through a network service. |
| [MappedQuantumAdapter](./Catalog/Mapped/MappedQuantumAdapter.json) | Empty mapped group; no activities or concrete adapters are declared. |
| [MappedQueueAdapter](./Catalog/Mapped/MappedQueueAdapter.json) | Queue reading, writing, acknowledgement, deferral, and message handling. |
| [MappedSatelliteAdapter](./Catalog/Mapped/MappedSatelliteAdapter.json) | Telemetry entry, signal, and message emission. |
| [MappedSessionAdapter](./Catalog/Mapped/MappedSessionAdapter.json) | Session lookup or registration. |
| [MappedStorageAdapter](./Catalog/Mapped/MappedStorageAdapter.json) | Resource read, write, delete, and existence checks across storage providers. |
| [MappedTokenAdapter](./Catalog/Mapped/MappedTokenAdapter.json) | Token value resolution from a path across token providers. |
| [MappedUtilityAdapter](./Catalog/Mapped/MappedUtilityAdapter.json) | Image resizing and overlay operations. |

## Condensers

These files are referenced by [MappedCondenserAdapter](./Catalog/Mapped/MappedCondenserAdapter.json).

| Catalog file | Description |
| --- | --- |
| [ConductionCondenser](./Catalog/Condensers/ConductionCondenser.json) | SovereignTrust conduction plan invocation. |
| [ConduitCondenser](./Catalog/Condensers/ConduitCondenser.json) | Plan processing through a conduit and phase graph construction. |
| [FabCondenser](./Catalog/Condensers/FabCondenser.json) | Fabrication condenser invocation. |
| [FormatCondenser](./Catalog/Condensers/FormatCondenser.json) | JSON, JSON array, XML, and text formatting. |
| [GraphCondenser](./Catalog/Condensers/GraphCondenser.json) | Graph condenser catalog with no declared activities. |
| [HydrationCondenser](./Catalog/Condensers/HydrationCondenser.json) | Hydration condenser invocation. |
| [MapCondenser](./Catalog/Condensers/MapCondenser.json) | Mapping values and invoking mapping operations. |
| [MemoryCondenser](./Catalog/Condensers/MemoryCondenser.json) | Memory content generation and a reserved persistence activity. |
| [MergeCondenser](./Catalog/Condensers/MergeCondenser.json) | Merging signal data. |
| [PlanCondenser](./Catalog/Condensers/PlanCondenser.json) | Plan and phase iteration, invocation, status, stopping, and step insertion. |
| [RestCondenser](./Catalog/Condensers/RestCondenser.json) | REST method activities for GET, HEAD, POST, PUT, PATCH, DELETE, and OPTIONS. |
| [TokenCondenser](./Catalog/Condensers/TokenCondenser.json) | Parsing and resolving a token. |
| [TransformCondenser](./Catalog/Condensers/TransformCondenser.json) | Signal projection, selection, injection, registration, cloning, and merging. |
