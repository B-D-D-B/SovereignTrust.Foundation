# IteratePhase ordering and limit implementation plan

Extend Plan Condenser `IteratePhase` so a plan can select the first N records after filtering and ordering. This is an implementation proposal; no implementation or runtime acceptance is claimed. Review history and identities belong in the [Working record](Working/Plan-Condenser-IteratePhase-Ordering-Limit-Working.md).

```json
{
  "Activity": "IteratePhase",
  "Config": {
    "Activity": "InvokePhase",
    "IterationArray": [
      { "Id": "C", "Meta": { "Rank": 3 } },
      { "Id": "A", "Meta": { "Rank": 1 } },
      { "Id": "B", "Meta": { "Rank": 2 } },
      { "Id": "B2", "Meta": { "Rank": 2 } }
    ],
    "OrderBy": "Meta.Rank",
    "OrderDirection": "ASC",
    "Limit": 2,
    "Threading": { "Enabled": false }
  }
}
```

The selected records are A, B. DESC selects C, B. Equal keys retain their input order, so B precedes B2 in either direction.

## Settings and validation

| Setting | Omitted or null | Accepted explicit value | Failure |
| --- | --- | --- | --- |
| `OrderBy` | Preserve input order | Trimmed item-relative dotted identifier path such as `Rank`, `Value` or `Meta.Rank` | Nonstring, blank or unsupported syntax, including `@` |
| `OrderDirection` | DESC | Trimmed case-insensitive ASC or DESC | Every other nonnull value, even without OrderBy |
| `Limit` | Unlimited | Native Int32/Int64 >= 0 | Negative, Boolean, string, floating/fractional value, array or object |

Direction alone preserves input order. Zero selects no records; positive N selects the first min(N, retained count). Limit counts selected records, regardless of child completion or success. A failed child retains existing behavior.

When OrderBy is absent/null, do not traverse or validate item keys or impose the new key-type restrictions. Existing scalar/record iteration and Filter behavior remain unchanged. With OrderBy active, validate its syntax and every retained key before applying Limit, including Limit=0. Validate configuration even for an empty input. Filtered-out records' keys are never inspected.

## Selection algorithm

Implement this pipeline in [PlanCondenser.ps1](../../Src/PowerShell/Classes/Adapters/Condenser/PlanCondenser.ps1), after current Filter processing and before the trace decision, empty return, warmup or cloning:

1. Resolve Config.OrderBy, Config.OrderDirection and Config.Limit from Plan using Resolve-PathFromDictionary with -SignalLevel "Information". OrderDirection explicitly uses -Default "Desc"; OrderBy and Limit use -Default $null. Missing/null direction therefore means DESC. Merge each returned Signal and fail on Critical, any nonnull SignalEntry.Exception or a thrown exception; use HasResult before GetResult. Validate resolved settings even on empty input.
2. Run existing filtering unchanged. If ordering is active, prepare each retained record's original position, original value and resolved key. Finish validation/key preparation before any iteration clone or launch.
3. Separate missing/null keys into a final bucket. Sort nonnull keys by the comparator below, preserving original positions for equal keys. Append the null bucket in original order. For DESC, reverse only the key comparison; never reverse the completed array or original-position tiebreaker.
4. Apply Limit to the resulting sequence. Cap Int64 limits against array count before converting to an index-sized integer. Avoid inclusive range expressions that mishandle zero/singleton arrays.
5. Use the selected array everywhere downstream. Assign indices 0 through selectedCount-1. Trace cardinality, serial arguments, worker values and WorkerContext.IterationArray must describe that same array.

Do not mutate the caller's array or records in the selection algorithm. Use the shared resolver for lookup and local class helpers for key-category validation/comparison; no shared resolver or threading API changes. Resolver-driven getters may have effects on caller objects; the selection algorithm cannot guarantee absence of those effects.

### Shared path resolution

Accept only `[A-Za-z_][A-Za-z0-9_]*` segments separated by single dots. Reject `@`, empty segments, internal whitespace, indexes, graph symbols, wildcards, comma fallbacks, pipes/default expressions and executable expressions. There is no scalar-self selector API.

For each retained nonnull item, resolve the configured trimmed item-relative path using Resolve-PathFromDictionary -Dictionary $item -Path $orderBy -Default $null -SignalLevel "Information". Every actual ordering key comes from that item's returned resolver Signal; there is no direct-self bypass. A null item is a null-bucket key without binding it to the resolver's mandatory Dictionary parameter. Preserve shared resolver container, property, case-matching and getter semantics; remove ReadIterationMember and its passive-container/PSNoteProperty/ambiguity rejection policy. The restricted OrderBy syntax remains a configuration guard, not a replacement traversal engine. Existing Filter resolution is unchanged.

Merge every lookup Signal into the operation before using its result. A returned Critical Signal, any returned entry with a nonnull Exception, or an exception thrown by lookup is an observable resolver failure: log Critical and return before cloning or dispatch, including Limit=0. Inspect structured Exception fields, never message wording. Missing/null/unresolved results without those failure indicators become null-bucket keys; do not promote informational missing-path entries. This includes the shared resolver's unsupported-container or ambiguous-name behavior where no structured exception is exposed.

Shared getters may execute. A read-only probe against current resolver source showed a throwing ScriptProperty executes once but returns no result, no Critical status and no SignalEntry.Exception; that unreported exception is therefore indistinguishable from a missing value through this interface and becomes a null key. A reflected CLR getter exception does produce SignalEntry.Exception and must be promoted to Critical. This explicit observability limit supersedes the earlier zero-getter and complete traversal-exception rejection requirements; do not change the shared resolver to recover those guarantees.

### Comparison and supported key types

All nonnull keys must share one category:

| Category | Comparison |
| --- | --- |
| String | StringComparer.OrdinalIgnoreCase; case-only differences are stable ties |
| Boolean | false before true |
| Exact numeric | Native SByte, Byte, Int16, UInt16, Int32, UInt32, Int64, UInt64 and Decimal only; normalize losslessly to Decimal and use Decimal.Compare |

All supported integral values fit Decimal exactly. Reject Single and Double, including finite values, NaN and infinities; reject enums, numeric strings mixed with numbers, mixed categories and complex key values. Never convert floating values to Decimal: that conversion can collapse distinct values. Tests of numeric/string/Boolean categories use records with a Value member and OrderBy="Value", exercising real per-item resolution. Null keys remain last in both directions.

### Threading and signal context

Clamp Warmup to selectedCount. Excluded records must never be cloned, called serially or submitted to the pool. Preserve current environment eligibility, MaxThreads, DebugInline, DebugWorkItemIndex, fallback and grid-reuse rules. Ordering controls selection/submission and index assignment, not parallel completion order.

Keep current IterationName and parent/pointer behavior. The signal registered by [Invoke-PlanIteration.ps1](../../Src/PowerShell/Utilities/Adapters/Condenser/Plan/Invoke-PlanIteration.ps1) must expose the selected value, contiguous IterationIndex and complete selected IterationArray. IteratePhase continues to have no aggregate public Result.

## File changes

| File | Required change |
| --- | --- |
| [PlanCondenser.ps1](../../Src/PowerShell/Classes/Adapters/Condenser/PlanCondenser.ps1) | Configuration/key shared-resolver reads, observable-exception guards, exact key-category/comparison helpers and selection before dispatch |
| [IteratePhase tests](../../Tests/PlanCondenser.IteratePhase.Tests.ps1) | Extend current serial/pool spies with clone/value/index/name/array assertions and the cases below |
| [Iteration helper tests](../../Tests/Invoke-PlanIteration.Tests.ps1) | Add real registered-signal array/index/name/pointer checks only where existing assertions do not already establish them |
| [PlanCondenser catalog](../../Src/PowerShell/Classes/Adapters/Catalog/Condensers/PlanCondenser.json) | Add OrderBy, OrderDirection and Limit properties/defaults/guidance; update affected array/filter/threading descriptions with selection precedence and limitations |
| [Attribution matrix](Working/Adapter-Index-Attribution-Matrix.json) and [owner shard](Working/Adapter-Index-Attribution-Matrix/Condensers/PlanCondenser.json) | Reconcile affected reads/defaults/references and current source identity, including shifted line references |
| [Result companion](../../Src/PowerShell/Classes/Adapters/ResultContracts/Condensers/PlanCondenser.json) | Refresh affected source evidence only; retain result semantics |
| [Troubleshooting shard](../../Src/PowerShell/Classes/Adapters/Catalog/Condensers/PlanCondenser-troubleshooting-invoke.json) and [manifest](../../Src/PowerShell/Classes/Adapters/Catalog/index-troubleshooting.json) | Source-verified new validation errors and matching owner source inventory/route projections; preserve unrelated/unresolved entries |
| [Required integration plan](../../../BDDB.Infrastructure/integration/sovereign-trust/content/test/plans/st-test-adapters-condenser.json) | Plan-selected positive routes, ordering/limit test phases, shared marker phase and disabled negative routes |
| [Condenser fixtures](../../../BDDB.Infrastructure/integration/sovereign-trust/content/test/fixtures/core/condenser-cases.json) and [case spec](../../../BDDB.Infrastructure/integration/sovereign-trust/content/test/specs/st-test-adapters-condenser-cases.json) | Immutable inputs/expectations and truthful authored coverage; guard fixture loading before consumers |

Follow the existing [catalog maintenance contract](../../Src/PowerShell/Classes/Adapters/Catalog/index.md) and [integration authoring guide](../../../BDDB.Documentation/Guides/Plan-Authoring/ST-Test-Plan-Authoring-Guide.md). Preserve encoding, BOM, line endings, formatting, existing routes/orders and unrelated bytes. No adapter membership/layout changes, shared policy edits, commits, publishing or provider effects.

## Acceptance cases

For source order C:3, A:1, B:2, B2:2:

| Configuration | Exact selected IDs |
| --- | --- |
| No new options | C,A,B,B2 |
| Explicit ASC with OrderBy | A,B,B2,C |
| DESC or omitted/null direction with OrderBy | C,B,B2,A |
| ASC + Limit2 | A,B |
| DESC + Limit2 | C,B |
| Limit2 only | C,A |
| Limit0 | none |
| Limit1 / exact count / count+1 / Int64.MaxValue | first / all / all / all in selected order |

Add missing/null keys and prove they remain last, stable in both directions. Filter out A and another record whose key would otherwise be invalid: ASC+Limit2 must select B,B2 without evaluating the excluded invalid key. Cover empty, singleton, all-null, dictionary/NoteProperty nesting, case matching, string/bool categories and original input preservation.

Numeric tests must distinguish the review counterexamples: Double [1.0000000000000002,1.0] and [1e-29,0.0] each fail before clones/serial/pool calls, in ASC/DESC and Limit0. Reject Single, NaN and infinities too. Typed supported input [Decimal.MaxValue, UInt64.MaxValue, Int64.MinValue, Decimal.MinValue, Decimal(1e-28), Decimal.Zero] sorts ASC to [Decimal.MinValue, Int64.MinValue, Decimal.Zero, Decimal(1e-28), UInt64.MaxValue, Decimal.MaxValue]; DESC reverses that ordering. Limit1 selects the exact extreme. Equal integral/Decimal values remain stable. Construct typed boundaries in unit tests; JSON numeric loading may produce Double.

Exercise the real shared-resolver/Invoke boundary without a resolver-success stub. Test dictionary/NoteProperty nesting, absent/null keys and shared unsupported/ambiguous traversal outcomes as nullable when no observable failure exists. Keep syntax and key-category rejections. A real throwing ScriptProperty must execute and exhibit the observed no-result/null-bucket behavior; use Limit=0 to isolate lookup side effects from existing clone serialization. A throwing reflected CLR getter at root and nested under a NoteProperty must execute, expose a structured exception and fail Critical before any clone/serial/pool call, including Limit=0. Also cover a successful method-backed getter and a configuration lookup exposing a structured exception. A narrowly scoped thrown-lookup test may supplement these real-resolver cases; it must preserve/restore the actual resolver and cannot replace the real boundaries. Every invalid configuration/key or observable resolver failure asserts Critical and zero clones/serial/pool calls. Unsupported keys remain unrestricted when ordering is omitted.

For explicit ASC selected [A,B,B2] and Warmup1, assert serial 0:A and pool work items 1:B,2:B2, with the complete selected array/name in both contexts. Change existing implicit-ASC unit scenarios to explicit ASC wherever their original oracle exercises ASC; add distinct omitted/null DESC cases. Limit below warmup creates no pool; zero creates no calls or clones. Check disabled threading, globally disabled parallelism, singleton fallback and DebugInline against identical selection. Preserve existing diagnostic/failure regressions.

### Integration assertions

Use the existing WriteFilterMarker pattern to create case+item+CondenserRunId markers containing Id, Meta.IterationIndex and Meta.IterationArray.Count. Append unique phase/step orders and Plan-selected routes; preserve DeferredHydrationPlan `@`, SkipRename and serial execution. Load/guard immutable fixture data before its consumers.

Each positive case ends with RecordTestResults, TestGroup `CondenserAdapter`, distinct `Plan.IteratePhase.OrderLimit.<Case>` TestName and native Boolean TestResult. Cover explicit ASC, default DESC, explicit DESC, stable ties/nulls, both directions with Limit2, limit-only, zero/one/exact/oversized/empty and filter precedence. Reconcile the existing named default case and its fixture/spec/marker expectations to C,B,B2,A (followed by stable null keys when present); explicit ASC cases retain their expected selection. Assert every selected marker's identity/index/cardinality and every excluded marker's absence. Zero/empty must have no attempt marker. Missing observations fail positive checks using existing fallback conventions. TestExpected is diagnostic, not the oracle.

Include omitted-operation and wrong-ID controls that demonstrate the expression rejects missing/false observations. Invalid configuration phases stay disabled in ordinary family dispatch; a failure-observing host executes them individually and requires a failed Signal plus absent attempt markers. Do not insert an intentionally failing case into normal successful family execution. Threaded runtime acceptance is not claimed by these serial JSON cases.

## Execution and verification

1. Revalidate reviewed source/policy/file identities and preserve exact preimages before edits. A mismatch stops dependent edits for affected revalidation; preserve unrelated working changes.
2. Implement the selection helpers/guards and affected unit assertions together; verify the actual clone/dispatch boundary.
3. Update catalog/evidence/troubleshooting projections and author integration fixtures/routes/assertions in the listed existing files.
4. Run these commands from the Foundation root in fresh PowerShell 7 processes:

```powershell
pwsh -NoProfile -File ./Tests/PlanCondenser.IteratePhase.Tests.ps1
pwsh -NoProfile -File ./Tests/Invoke-PlanIteration.Tests.ps1
pwsh -NoProfile -File ./Tests/PlanCondenser.InvokePhaseName.Tests.ps1
git diff --check
git -C ../BDDB.Infrastructure diff --check
```

Parse each changed JSON using ConvertFrom-Json -Depth 100 -ErrorAction Stop and changed PowerShell using Parser.ParseFile, requiring zero parse errors. Target static checks at property/default uniqueness, source hashes/references, error/route correspondence, unchanged membership, unique phase/step orders, fixture selection and route→phase→record links. Record actual command results and failures; static checks and spies prove only their exercised boundaries.

5. Run required host integration only after a supported isolated selected host is available. The existing [ST-Test.ps1](../../../BDDB.Infrastructure/integration/sovereign-trust/ST-Test.ps1) command is `pwsh -NoProfile -File ./integration/sovereign-trust/ST-Test.ps1` from Infrastructure root, but it hardcodes the full-suite config and has no selected-case/config-path switch. Do not run that current full provider selection for this change. Its `-ExecuteReviewedRuntime:$false` switch establishes input preflight only.

The host prerequisite is a bounded supported selection with current modules/source, loaded core fixture, new positive identities in selected ExpectedResults, isolated writable content/result/event roots, cleanup and an individual-negative failure observer. If unavailable, only dependent host execution and overall behavioral acceptance remain blocked pending a separately reviewed bounded host-selection change. Do not invent runner flags or extend this plan with a new harness. No provider credentials are needed for these local-content Plan cases. Require current-run unique events, native true result leaves, exact inventory, exclusion/no-attempt markers and rejected controls. Record exact host configuration/module identities and receipts. Actual runspace tests additionally need EnvironmentDetails parallelism/mapped worker access and are outside this serial integration claim.

6. Freeze the complete changed-file snapshot, actual checks, failures/skips and host limitations for one independent result review. Plan readiness is not software acceptance; preserve the required host gate. On unknown state, failed mutation verification or unsafe recovery, stop affected work under existing project safeguards; do not overwrite competing work or broaden scope.
