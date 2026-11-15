using System;
using System.Collections;
using System.Text.RegularExpressions;
using SignalGraph;
using SovereignTrust.Foundation.Classes.Conduction;

namespace SovereignTrust.Foundation.Wrappers.Adapters;

public sealed class FabSourceIdentity
{
    public string Kind { get; internal set; }
    public string Slot { get; internal set; }
    public string VirtualPath { get; internal set; }
    public string FullType { get; internal set; }
}
public sealed class FabObservation
{
    public bool SourceMapping { get; internal set; }
    public string ModuleName { get; internal set; }
    public string ClassName { get; internal set; }
    public string MappedSlot { get; internal set; }
    public string JacketVirtualPath { get; internal set; }
    public bool MissingSlotAbsent { get; internal set; }
    public string RegistrationState { get; internal set; }
}
public sealed class FabRegistry
{
    readonly Conductor conductor;
    internal FabRegistry(Conductor conductor) { this.conductor = conductor; }
    public Signal Register(IDictionary jacket, Signal context, bool lazy = true, bool retry = false)
    {
        var op = Signal.Start("FabCondenser.Invoke", context);
        try
        {
            string path = Convert.ToString(jacket?["VirtualPath"]);
            var parts = (path ?? "").Split('.');
            if (parts.Length < 5 || !Regex.IsMatch(parts[2], "^[A-Za-z]+$") || !Regex.IsMatch(parts[4], "^[A-Za-z0-9_-]+$"))
                return op.LogMessage("Critical", "Selected source jacket has no consistent Kind, Slot and VirtualPath.");
            string kind = parts[2], slot = parts[4];
            if (jacket.Contains("Kind") && !string.Equals(Convert.ToString(jacket["Kind"]), kind, StringComparison.Ordinal) || jacket.Contains("Slot") && !string.Equals(Convert.ToString(jacket["Slot"]), slot, StringComparison.Ordinal))
                return op.LogMessage("Critical", "Selected source jacket has no consistent Kind, Slot and VirtualPath.");
            var family = conductor.GetFamily(kind);
            if (family == null) return op.LogMessage("Critical", "Unknown mapped family: " + kind);
            string fullType = Convert.ToString(jacket["FullType"]);
            if (string.IsNullOrWhiteSpace(fullType)) fullType = kind + "_" + parts[3];
            var configuration = Paths.NewDictionary();
            foreach (DictionaryEntry pair in jacket) configuration[pair.Key] = pair.Value;
            configuration["Kind"] = kind; configuration["Slot"] = slot;
            var source = new FabSourceIdentity { Kind = kind, Slot = slot, VirtualPath = path, FullType = fullType };
            var definition = new AdapterDefinition
            {
                Family = kind, Jacket = configuration, Context = context, Lazy = lazy, RetryFailedResolution = retry,
                Factory = () => conductor.CreateLeaf(fullType), Hydrate = conductor.ConfigurationHydrator
            };
            // Publish the selected source before eager Register invokes its factory.
            // A duplicate must leave the previously selected source and cache intact.
            if (conductor.GetRegistration(kind + "." + slot) != null)
            {
                op.MergeSignal(conductor.Register(kind + "." + slot, definition));
                return op;
            }
            family.Graph.RegisterResultAsSignal(slot, null);
            family.Graph.Grid[slot].AddProperty("FabSourceIdentity", source);
            var registered = conductor.Register(kind + "." + slot, definition);
            var registration = conductor.GetRegistration(kind + "." + slot);
            family.Graph.RegisterResultAsSignal(slot, registration.State == AdapterState.Resolved ? registration.Instance : registration);
            family.Graph.Grid[slot].AddProperty("FabSourceIdentity", source);
            if (op.MergeSignalAndVerifyFailure(registered)) return op;
            conductor.FabRegistrationCount++;
            op.Result = registration.State == AdapterState.Resolved ? registration.Instance : registration;
        }
        catch (Exception error) { op.LogMessage("Critical", error.InnerException?.Message ?? error.Message, null, error); }
        return op;
    }
    public Signal Observe(string kind, string slot, string absentSlot, Signal context)
    {
        var op = Signal.Start("FabCondenser.ObserveMappedAdapter", context);
        if (string.IsNullOrWhiteSpace(kind) || string.IsNullOrWhiteSpace(slot) || string.IsNullOrWhiteSpace(absentSlot) || slot.Equals(absentSlot, StringComparison.OrdinalIgnoreCase) || !Regex.IsMatch(kind, "^[A-Za-z]+$") || !Regex.IsMatch(slot, "^[A-Za-z0-9_-]+$") || !Regex.IsMatch(absentSlot, "^[A-Za-z0-9_-]+$"))
            return op.LogMessage("Critical", "ObserveMappedAdapter requires distinct, nonempty Kind, Slot and AbsentSlot.");
        var family = conductor.GetFamily(kind);
        if (family == null || !family.Graph.Grid.Contains(slot)) return op.LogMessage("Critical", "Selected mapped slot is missing.");
        var node = family.Graph.Grid[slot];
        if (node.GetProperty("FabSourceIdentity") is not FabSourceIdentity source || source.Kind != kind || source.Slot != slot || source.VirtualPath.Split('.')[2] != kind || source.VirtualPath.Split('.')[4] != slot)
            return op.LogMessage("Critical", "Mapped slot has no matching Fab source identity.");
        var resolved = family.ResolveSlot(slot);
        if (op.MergeSignalAndVerifyFailure(resolved)) return op;
        var instance = resolved.Result;
        var expected = conductor.TypeResolver(source.FullType);
        if (instance == null || expected != instance.GetType()) return op.LogMessage("Critical", "Resolved instance type does not match the source-selected type.");
        var instanceSignal = instance.GetType().GetProperty("Signal")?.GetValue(instance) as Signal;
        var jacketValue = instanceSignal?.GetJacketResult(true);
        var jacket = jacketValue == null ? null : conductor.MetadataConverter?.Invoke(jacketValue) ?? jacketValue as IDictionary;
        var instancePath = Convert.ToString(jacket?["VirtualPath"]);
        if (jacket == null || Convert.ToString(jacket["Kind"]) != kind || Convert.ToString(jacket["Slot"]) != slot || string.IsNullOrWhiteSpace(instancePath))
            return op.LogMessage("Critical", "Constructed jacket identity is missing or mismatched.");
        if (string.IsNullOrWhiteSpace(conductor.BusinessModuleName)) return op.LogMessage("Critical", "Selected business module identity is missing.");
        var registration = conductor.GetRegistration(kind + "." + slot);
        if (registration == null || registration.State != AdapterState.Resolved || !ReferenceEquals(registration.Instance, instance) || !ReferenceEquals(node.Result, instance))
            return op.LogMessage("Critical", "Lazy registration did not transition to the cached instance.");
        conductor.FabObservationCount++;
        op.Result = new FabObservation { SourceMapping = source.VirtualPath == instancePath, ModuleName = conductor.BusinessModuleName, ClassName = instance.GetType().Name, MappedSlot = slot, JacketVirtualPath = instancePath, MissingSlotAbsent = !family.Graph.Grid.Contains(absentSlot), RegistrationState = registration.State.ToString() };
        return op;
    }
}
