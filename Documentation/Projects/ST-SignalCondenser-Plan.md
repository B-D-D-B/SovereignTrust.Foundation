# ST SignalCondenser: future implementation plan

## Purpose and decision

Provide a small ST plan step that writes content-driven Signal entries at `Information`, `Warning`, or `Critical`, plus a typed assertion step that turns failed validation into a Critical Signal with a diagnostic. This is a separate Foundation capability for plan and integration-test authors. It does not modify an intelligence adapter, formatter, or test runner. This document proposes future work only; no behavior or acceptance is claimed.

**Default exit rule:** preserve the current invariant: Critical fails the current phase and propagates to the containing plan/serial iteration. The owner may instead request handled phase-only continuation, but that requires a distinct, reviewed parent control contract; it must not be inferred from `Signal.Failure()` or hidden by muting Critical. Until that decision, implement and test plan-stop behavior only.

## Observed baseline and design choice

`Signal.LogMessage(level,message,tags)` appends a `SignalEntry` and raises the Signal level; `Failure()` is true for level `Critical` ([Signal.ps1](../../../../SignalGraph/Src/PowerShell/SignalGraph/Classes/Signal.ps1), external sibling). `MemoryCondenser.Generate` merges each mapped step result and returns on failure before it can advance to the next step. `Invoke-PlanPhase` merges the Generate result and returns on failure. `PlanCondenser.IteratePhase` merges each serial `Invoke-PlanIteration` result and returns on failure. `MappedCondenserAdapter.Invoke` also merges a failed condenser result and records its own Critical entry. Thus a Critical assertion is a plan failure, not merely an exit from one phase. `ExitAfterAdapter` skips result formatting/transform/hydration; it does not stop phase or plan execution. `ExitAfterAdapterNoResult` exits Generate when the adapter returned no Result, and is unsuitable as a success control for assertions.

Choose `Condenser.Signal` with two activities: `Log` and `Assert`. `Log` is justified because plan authors need contextual Information and Warning entries as well as Critical diagnostics. `Assert` is distinct because it inspects a *native typed value* and never delegates correctness to a caller-authored sentinel, string interpolation, or truthiness conversion. A `Plan.Assert`-only addition would cover validation but would leave content-driven informational/warning logging without an equivalent step; adding both would duplicate dispatch and contract surface. Do not introduce a new assertion language, generic comparator registry, or runner control framework.

## Proposed contract

| Activity | Inputs in `Config` | Success | Invalid input / failed assertion |
| --- | --- | --- | --- |
| `Log` | `Level` is exactly Information, Warning, or Critical; `Message` is a bounded nonblank literal or a resolved scalar string; optional `MessagePath` supplies a typed source and is mutually exclusive with `Message` | One entry at requested level; return a Result receipt so ordinary Generate continues for Information/Warning | Malformed level/message/source is a Critical diagnostic. Requested Critical logs a Critical entry and follows current failure propagation. |
| `Assert` | `ValuePath` resolves a typed value from the Item graph; `Predicate` initially `IsString`, `IsNonBlankString`, or `EqualsString`; `Expected` required only for `EqualsString`; `Message` is a bounded diagnostic | One Information entry and a Result receipt; no mutation of asserted content | Missing path, unsupported predicate, wrong native type, mismatch or malformed diagnostic produces Critical with bounded path/predicate context. |

For `Assert`, resolve the graph value without converting it to `[string]` before type comparison. `IsString` requires `-is [string]`; `IsNonBlankString` additionally rejects empty/whitespace; `EqualsString` requires a native string and ordinal equality to a native-string `Expected`. A JSON number, Boolean, array or object whose displayed text matches `Expected` must fail. A caller-owned field such as `__Rejected__` must not provide the success/failure oracle. No defaulting an absent `ValuePath` to empty text. Resolve once; reject missing or ambiguous results. Keep input paths and emitted messages bounded and avoid copying full untrusted content into logs. Return a small receipt (activity, predicate/level, passed status) for successful steps; a failed result need not carry a Result because Critical already stops Generate.

`Log` can use a literal `Message` or a `MessagePath` that resolves a native scalar string. Require exactly one origin; reject arrays/objects, null and blank text, and bound length before logging. Never evaluate message text as a token expression. A fixed diagnostic may include a short step name and path but no arbitrary object serialization or secret value. Use a maximum of 2,048 UTF-16 code units for Message and Expected, 512 for paths, and 2,560 for any emitted entry. Reject oversize inputs before resolution or logging; do not truncate a successful requested message. Assert Message must be a nonblank native string. Level and Predicate are case-sensitive native-string enum names; Expected is forbidden outside EqualsString. Critical Log and every invalid/failed operation return no Result. A successful receipt is a PSCustomObject with Activity and Passed=true plus Level for Log or Predicate for Assert. No request for tags or Recovery/Mute flags in v1, since those can alter severity propagation.

### Representative plan steps

Resolve ValuePath/MessagePath against ItemSignal with a private scalar path walker in SignalCondenser. Accept dot-separated segments matching `[A-Za-z_][A-Za-z0-9_]*` or the existing ST symbols `*`=Pointer, `#`=Grid, `@`=Result, `%`=Jacket, `~`=Control. Require every segment to exist as one dictionary key or property; reject null, collection traversal, filters, comma fallbacks, quoted segments, XPath tails and empty segments. Read the final property directly without pipeline enumeration, conversion or GetResult unwrapping; empty and single-element arrays must remain arrays and fail string predicates. This deliberately bounded subset supports the example and avoids the generic resolver's fallback/default and enumeration behavior. Do not merge generic resolver diagnostics or serialize exceptions/values into Signal entries. A failed assertion uses the validated Message plus bounded path/predicate; malformed configuration uses a fixed diagnostic. Passing Assert emits `Assertion passed.` at Information. No changes to SignalGraph are required.

```json
{
  "Name": "ReportSelection", "Order": 0,
  "Adapter": "Condenser.Signal", "Activity": "Log",
  "ExitAfterAdapter": true,
  "Config": { "Level": "Information", "Message": "Checking selected profile" }
}
```

```json
{
  "Name": "RequirePromptText", "Order": 1,
  "Adapter": "Condenser.Signal", "Activity": "Assert",
  "ExitAfterAdapter": true,
  "Config": {
    "ValuePath": "*.#.BFLFormatInput.@.Prompt.Text",
    "Predicate": "IsNonBlankString",
    "Message": "Prompt.Text must be a nonblank native string"
  }
}
```

A Warning `Log` step may follow a passing assertion in the same phase. A Critical `Log` or failed `Assert` stops subsequent steps and the containing plan under the default rule. Put a succeeding phase after a failing phase in an integration fixture to assert that it does *not* run; do not describe this as automatic phase-only continuation.

## Implementation index

| Target | Planned change and check |
| --- | --- |
| `Src/PowerShell/Classes/Adapters/Condenser/SignalCondenser.ps1` | New class with guarded `Log`/`Assert` dispatch, native type validation, bounded diagnostics and Signal return. Model constructor/invoke shape on existing condensers. |
| `Src/PowerShell/Utilities/Graph/Resolve-PathGraphCondenserAdapter.ps1` | Register `SignalCondenser` in the mapped graph so `Condenser.Signal` dispatch resolves. |
| `Src/PowerShell/SovereignTrust.Foundation.psm1` | Dot-source the new class with the other condensers before graph registration; verify module import. The catalog alone does not load code. |
| `Src/PowerShell/Classes/Adapters/Catalog/Condensers/SignalCondenser.json` | Describe exact properties, defaults, levels, Result semantics and when to use. |
| `Src/PowerShell/Classes/Adapters/Catalog/Mapped/MappedCondenserAdapter.json`, `Src/PowerShell/Classes/Adapters/Catalog/index.json` | Add condenser discovery entries. |
| `Src/PowerShell/Classes/Adapters/ResultContracts/Condensers/SignalCondenser.json` | Declare the small receipt and failure/no-Result behavior using the established result schema. |
| `Tests/SignalCondenser.Tests.ps1` (new), `Tests/PlanCondenser.IteratePhase.Tests.ps1` (affected) | Unit and end-to-end phase/serial iteration assertions below; correct IteratePhase test's existing stale import to `../../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1`. Add minimal fixture plan JSON under `Tests/Fixtures/` only if the existing harness needs it. The new test owns real mapped-boundary integration; the existing IteratePhase file uses stubs and alone cannot establish it. |

The ST plan in `SovereignTrust.Adapters/Plans/Intelligence/Format-BFLFlux2Prompt.json` shows current phase/step fields and a sentinel-based `RequireNonemptyText` pattern; it is migration context, not an edit target for this function. A numeric `Prompt.Text` such as `42` can be rendered as text while a caller-owned `__Rejected__` can be populated to bypass a missing-path sentinel. An `Assert` on `Prompt.Text` with `IsNonBlankString` must fail on the number regardless of `__Rejected__`. For an ST test-plan case, a fixture phase asserts a native string result, then records "validation passed"; substitute a Boolean result and verify the diagnostic is Critical, that message is absent, and a following phase/serial iteration does not run. Existing Transform/Plan steps remain valid; do not silently rewrite their plans or change their assertion meaning.

## Ordered future execution and evidence

1. Before code changes, revalidate the indexed loader/registration paths and source baselines against this reviewed revision; retain default Critical propagation. Register the future implementation function with Sol 6 medium worker and distinct Astra 6 medium reviewer, Normal track, using this exact D1–D8 READY under SP-01/SP-02. Apply SP-01 safe-mutation safeguards; a changed consequential contract needs affected READY. If the owner chooses phase-only continuation, first specify a separate status/handling contract and affected parent propagation changes, then seek affected READY. Do not implement a guessed continuation mode.
2. Add the class and registration/catalog/result contract in the indexed files. Use the existing mapped slot path and return Signal discipline. Keep Critical propagation through Memory, Invoke-PlanPhase and serial IteratePhase unchanged for the default.
3. Add direct tests for `Log`: each of three levels writes exactly the requested content and severity; Information/Warning do not fail; Critical fails. Reject missing/ambiguous origin, nonstring path result, blank/oversize message, invalid level and unsupported activity. Assert no unbounded value leaks in diagnostics.
4. Add direct tests for `Assert`: native string pass for all predicates; string mismatch, null/missing path, blank for nonblank, number, Boolean, array and object fail even when textual representation matches. Include a caller-controlled sentinel key populated with the expected text and show that assertion still fails on the actual wrong-typed value. Verify exact entry level/message and receipt presence only on success. Include zero/one/multiple-element arrays, case-sensitive enums/equality, absent/nonstring/forbidden Expected, ambiguous/invalid path syntax, null intermediate nodes, literal token-shaped messages, and length-limit/limit+1 cases for message, path and Expected. Reject array intermediate traversal even when its sole element has a matching property; assert original graph bytes/values are unchanged.
5. Add a real mapped `Condenser.Signal` phase fixture: passing assertion allows the following step and phase; Warning allows the following step; failed assertion/Critical Log prevents later steps, later serial iterations and later phases through the actual Generate/Invoke-PlanPhase/IteratePhase boundary. Verify the failing output retains the original diagnostic despite mapped wrapper entries. Test existing `ExitAfterAdapter` behavior is unaffected; do not use `ExitAfterAdapterNoResult` to claim success.
6. From the Foundation root run `pwsh -NoProfile -File ./Tests/SignalCondenser.Tests.ps1` and `pwsh -NoProfile -File ./Tests/PlanCondenser.IteratePhase.Tests.ps1` in separate processes (the existing tests declare stub classes). Require zero exit codes and explicit assertion counts. The new test must load sibling `../SignalGraph/Src/PowerShell/SignalGraph/SignalGraph.psd1` and the actual `./Src/PowerShell/SovereignTrust.Foundation.psd1` manifest in a fresh process, verifying its RequiredModules dependency resolves; the manifest loads the indexed psm1. Also parse the four changed catalog/result JSON files with ConvertFrom-Json, assert discovery references resolve exactly once, both activities and receipt/failure contracts agree with tests, and resultEvidence hashes/line references match final implementation source. Incorporate these bounded catalog assertions in the new test; do not assume a catalog validator exists. Record exact commands, pass/fail/skip counts, source identity and any unsupported integration boundary. Freeze the aggregate result for independent R1–R8 review. No provider call is needed for this local behavior.

Stop dependent work if module load order, path resolution, result-contract schema, catalog ownership or Critical propagation differs from the observed baseline, if the phase-only decision is required by the owner but unresolved, or if an unsafe/conflicting file state prevents a protected edit. A demand for phase-only continuation, generic workflow control, more predicates, or a logging registry splits into a separately reviewed scope; do not enlarge this function recursively. Preserve evidence and seek affected D1–D8 review when scope, semantics or oracle changes. Document readiness is separate from observed software behavior and Git publication.
