# Adapter catalog

This is a reading guide to [index.json](./index.json). The JSON file is the catalog manifest; the linked files below hold the adapter and condenser inventories. Descriptions summarize declared activities and do not imply that every activity is implemented.

## Choosing an owner, activity and property

`whenToUse` is authoring guidance in the catalog, not a property to copy into a runtime plan. Read it in three locations:

- **Owner:** on a root `mappedAdapters` entry (including the inline template) or a root `condensers` entry, to choose the owner and follow its `file` link when present. Choose PlanCondenser directly from `condensers`.
- **Activity:** on an activity object in the owning catalog, to choose an operation and recognize reserved or unimplemented activities.
- **Property:** on an activity `properties` object, to decide when that contextual input is needed or should be omitted.

The manifest retains data-format `version: 1`; `layoutVersion: 2` identifies the direct root condenser navigation. Root `condensers` is the plan-writer navigation authority. The nested `MappedCondenserAdapter.concreteAdapters` references retain structural grouping and must have the same unique names, order and resolved catalog targets; owner guidance is not duplicated there.

Guidance is being added by owner; its absence does not imply support or applicability. Empty owners remain empty. Consult the declared activity and current source when guidance is absent.

## Troubleshooting

The [troubleshooting manifest](./index-troubleshooting.json) and [troubleshooting authoring and retrieval guide](./index-troubleshooting.md) are a separate error-triggered index. Normal plan authoring and review use the ordinary catalog guidance here. A relevant observed error plus verified adapter identity and activity context can select one matching constructor, invoke or named concrete part and only its matching entry. These Markdown links are for discovery; they do not request preloading, recursively following links into prompt context, provider retries, or execution of corrections. Unknown or ambiguous errors do not load any part.

## Mapped adapters

The root manifest also contains `MappedAdapterTemplate` inline, with no activities or concrete adapters.

| Catalog file | Description |
| --- | --- |
| [MappedCondenserAdapter](./Mapped/MappedCondenserAdapter.json) | Groups the 15 concrete condenser catalogs listed below; it declares no activities at the mapped level. |
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
| [MappedUtilityAdapter](./Mapped/MappedUtilityAdapter.json) | Image resizing, inspection, and overlay operations. |

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
| [ProcessCondenser](./Condensers/ProcessCondenser.json) | Bounded native process invocation with binary stream capture. |
| [RestCondenser](./Condensers/RestCondenser.json) | REST method activities for GET, HEAD, POST, PUT, PATCH, DELETE, and OPTIONS. |
| [SignalCondenser](./Condensers/SignalCondenser.json) | Signal logging and assertion activities. |
| [TokenCondenser](./Condensers/TokenCondenser.json) | Parsing and resolving a token. |
| [TransformCondenser](./Condensers/TransformCondenser.json) | Signal projection, selection, injection, registration, cloning, and merging. |

## Keeping the catalog in sync

- **Add or remove a mapped adapter:** change the entries in [index.json](./index.json) and the matching [mapped catalog](./Mapped/); update the mapped table above. For a condenser, reconcile the root `condensers` entries in [index.json](./index.json) with the nested references in [MappedCondenserAdapter](./Mapped/MappedCondenserAdapter.json), preserving equal ordered names and resolved targets; update the matching [condenser catalog](./Condensers/) and condenser table above.
- **Change a declared activity or input:** update its owning catalog file under [Mapped](./Mapped/) or [Condensers](./Condensers/), including affected `properties`, adapter-specific `default`, and `whenToUse` guidance. Update the [attribution matrix](../../../../../Documentation/Projects/Working/Adapter-Index-Attribution-Matrix.json) and its [owner shard](../../../../../Documentation/Projects/Working/Adapter-Index-Attribution-Matrix/) when the source-backed inventory, attribution, or source identity changes. Revise a table description here only if its summary changes.
- **Change an observable result:** update the owning catalog's activity `result` and its linked companion under [ResultContracts](../ResultContracts/) when the result contract or its evidence changes. Check affected result consumers and tests.
- **Change implementation or dispatch:** reconcile the affected catalog declarations, matrix evidence, result companion, and [adapter tests](../../../../../Tests/) according to what changed; an implementation edit alone does not require rewriting every document. The matrix is retained source-attribution evidence. The [activity-properties plan](../../../../../Documentation/Projects/Working/Adapter-Index-Activity-Properties-Plan.md) records historical decisions, while the manifest and catalog files above hold the current inventory.

### Troubleshooting maintenance

- **Add an owner or concrete:** establish ordinary membership in [index.json](./index.json) and, for condensers, the nested [MappedCondenserAdapter](./Mapped/MappedCondenserAdapter.json). Inspect direct emitted errors, update the troubleshooting owner status, and add source-verified entries/routes in the canonical suffixed shard only when supported. A new concrete under a mapped owner updates that mapped owner's selectors. No verified error means a truthful inspected status, not a filler recipe.
- **Remove an owner or concrete:** reconcile live membership and remove only obsolete troubleshooting selectors/routes and any shard left unreferenced by an authorized change. Preserve review history and entries still used by another concrete.
- **Change an emitted error, guard or correction:** re-read direct source and update exact text or bounded pattern, trigger, causes, diagnostics, conditional correction, verification, limitations, provenance and manifest projection together. Keep aliases distinct; unresolved reports have no automatic route.
- **Change result or dispatch behavior:** follow the ordinary result-contract, catalog and matrix duties above. Revisit troubleshooting when error ownership, activity/adapter selector, forwarded meaning or recipe changes; an unrelated result-only change does not rewrite every troubleshooting file.
- **Validate:** parse affected JSON, check safe paths, current source identities, route projections, selector ambiguity, owner membership, links and ordinary-context exclusion. Recheck changed dependencies and retain unknown/stale claims explicitly. Static documentation checks do not prove runtime or provider success. See the [v2 troubleshooting guide](./index-troubleshooting.md) for constructor/invoke/concrete part classification, owner-level unverified candidates, sourceInventory and targeted retrieval. Maintain the exact matching owner part and route together.
