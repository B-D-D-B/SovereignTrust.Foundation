using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using Newtonsoft.Json.Linq;
using SignalGraph;

namespace SovereignTrust.Foundation.Classes.Conduction;

public enum AdapterState { Registered, Resolving, Resolved, Failed }

public sealed class AdapterDefinition
{
    public string Family { get; set; }
    public Type Type { get; set; }
    public Func<object> Factory { get; set; }
    public object Instance { get; set; }
    public object Manifest { get; set; }
    public object Jacket { get; set; }
    public object Context { get; set; }
    public Func<object, object, Signal> Hydrate { get; set; }
    public bool Lazy { get; set; } = true;
    public bool RetryFailedResolution { get; set; }
}

public sealed class AdapterRegistration
{
    internal readonly object Sync = new();
    public string Slot { get; internal set; }
    public AdapterDefinition Definition { get; internal set; }
    public AdapterState State { get; internal set; } = AdapterState.Registered;
    public object Instance { get; internal set; }
    public object Configuration { get; internal set; }
    public Signal Failure { get; internal set; }
    public int Attempts { get; internal set; }
}

public sealed partial class Conductor
{
    readonly Dictionary<string, AdapterRegistration> registrations = new(StringComparer.OrdinalIgnoreCase);
    readonly object registrySync = new();
    public Signal Signal { get; }
    public Graph Memory { get; }
    public Graph AdapterRegistry { get; }
    public object Context { get; }
    public int DispatchCount { get; internal set; }
    public IReadOnlyCollection<string> Slots { get { lock (registrySync) return registrations.Keys.ToArray(); } }

    public Conductor(object context = null)
    {
        Context = context;
        Signal = SignalGraph.Signal.Start("Conductor");
        Memory = Signal.CreateGraph();
        AdapterRegistry = (Graph)Graph.Start("NativeAdapterRegistry", Signal, true).Result;
    }

    Conductor(Signal signal, Graph memory, object context)
    {
        Signal = signal;
        Memory = memory;
        Context = context;
        AdapterRegistry = (Graph)Graph.Start("NativeAdapterRegistry", signal, true).Result;
    }

    public static Conductor Adopt(Signal signal, object context)
    {
        if (signal == null || signal.Pointer is not Graph memory)
            throw new ArgumentException("A canonical Signal with an existing Graph pointer is required.");
        return new Conductor(signal, memory, context);
    }

    public AdapterRegistration GetRegistration(string slot)
    {
        if (string.IsNullOrWhiteSpace(slot)) return null;
        lock (registrySync) return registrations.TryGetValue(slot, out var found) ? found : null;
    }

    public Signal Register(string slot, AdapterDefinition definition, bool softFailure = false)
    {
        var op = SignalGraph.Signal.Start("RegisterAdapter:" + slot, Signal);
        if (string.IsNullOrWhiteSpace(slot) || definition == null)
            return op.LogMessage("Critical", "A nonblank slot and adapter definition are required.");
        AdapterRegistration registration;
        lock (registrySync)
        {
            if (registrations.TryGetValue(slot, out var previous))
            {
                op.Result = previous;
                return op.LogMessage(softFailure ? "Warning" : "Critical", "Adapter slot already registered: " + slot);
            }
            registration = new AdapterRegistration { Slot = slot, Definition = definition };
            registrations.Add(slot, registration);
            AdapterRegistry.RegisterResultAsSignal(slot, registration);
        }
        op.Result = registration;
        if (!definition.Lazy) op.MergeSignal(Resolve(slot));
        return op;
    }

    public Signal Resolve(string slot, object fallbackContext = null)
    {
        var op = SignalGraph.Signal.Start("ResolveAdapter:" + slot, Signal);
        var registration = GetRegistration(slot);
        if (registration == null) return op.LogMessage("Critical", "Unknown adapter slot: " + slot);
        lock (registration.Sync)
        {
            if (registration.State == AdapterState.Resolved)
            {
                op.Result = registration.Instance;
                return op;
            }
            if (registration.State == AdapterState.Resolving)
                return op.LogMessage("Critical", "Circular adapter resolution: " + slot);
            if (registration.State == AdapterState.Failed && !registration.Definition.RetryFailedResolution)
                return registration.Failure;
            registration.State = AdapterState.Resolving;
            registration.Attempts++;
            try
            {
                var definition = registration.Definition;
                var instance = definition.Instance ?? definition.Factory?.Invoke();
                if (instance == null && definition.Type != null)
                    instance = Activator.CreateInstance(definition.Type);
                if (instance == null) throw new InvalidOperationException("Adapter type/factory did not create an instance.");
                // An explicit instance is already resolved by its caller; do not
                // rehydrate or reconstruct that source-compatible eager object.
                if (definition.Instance != null)
                {
                    registration.Instance = instance;
                    registration.State = AdapterState.Resolved;
                    registration.Failure = null;
                    op.Result = instance;
                    return op;
                }
                var configuration = MergeConfiguration(definition.Manifest, definition.Jacket);
                registration.Configuration = configuration;
                if (definition.Hydrate != null)
                {
                    var hydration = definition.Hydrate(configuration, definition.Context ?? fallbackContext ?? Context);
                    if (hydration == null) throw new InvalidOperationException("Hydration returned no Signal.");
                    op.MergeSignal(hydration);
                    if (op.Failure()) return Fail(registration, op);
                    if (hydration.HasResult()) configuration = hydration.Result;
                    registration.Configuration = configuration;
                }
                var hooks = instance.GetType().GetMethods().Where(m => m.Name == "Construct").ToArray();
                if (hooks.Length != 0)
                {
                    var hook = hooks.FirstOrDefault(m => m.GetParameters().Length == 1)
                        ?? throw new InvalidOperationException("Construct must accept one configuration argument.");
                    var constructed = hook.Invoke(instance, new[] { configuration });
                    if (constructed is not Signal constructedSignal)
                        throw new InvalidOperationException("Construct did not return the canonical Signal.");
                    op.MergeSignal(constructedSignal);
                    if (op.Failure()) return Fail(registration, op);
                }
                registration.Instance = instance;
                registration.State = AdapterState.Resolved;
                registration.Failure = null;
                op.Result = instance;
            }
            catch (Exception exception)
            {
                var cause = exception is TargetInvocationException invocation && invocation.InnerException != null ? invocation.InnerException : exception;
                op.LogMessage("Critical", cause.Message, null, cause);
                return Fail(registration, op);
            }
            return op;
        }
    }

    static Signal Fail(AdapterRegistration registration, Signal failure)
    {
        registration.State = AdapterState.Failed;
        registration.Failure = failure;
        return failure;
    }

    static object MergeConfiguration(object manifest, object jacket, int depth = 0)
    {
        if (depth > 20) throw new InvalidOperationException("Adapter configuration exceeds the source default merge depth (20).");
        manifest = NormalizeJsonValue(manifest);
        jacket = NormalizeJsonValue(jacket);
        if (manifest is not IDictionary && jacket is not IDictionary) return jacket ?? manifest;
        var merged = Paths.NewDictionary();
        if (manifest is IDictionary baseValues) foreach (DictionaryEntry pair in baseValues) merged[pair.Key] = CloneConfiguration(pair.Value, depth + 1);
        if (jacket is IDictionary overlay) foreach (DictionaryEntry pair in overlay)
        {
            if (pair.Value == null) continue;
            merged[pair.Key] = MergeValue(merged.Contains(pair.Key) ? merged[pair.Key] : null, pair.Value, depth + 1);
        }
        return merged;
    }
    static object MergeValue(object previous, object next, int depth)
    {
        if (previous is IDictionary && next is IDictionary) return MergeConfiguration(previous, next, depth);
        if (previous is IList before && next is IList after)
        {
            var merged = before.Cast<object>().Select(value => CloneConfiguration(value, depth + 1)).ToList();
            for (int i = 0; i < after.Count; i++)
            {
                if (i < merged.Count) merged[i] = after[i] == null ? merged[i] : MergeValue(merged[i], after[i], depth + 1);
                else merged.Add(CloneConfiguration(after[i], depth + 1));
            }
            return merged;
        }
        return CloneConfiguration(next, depth);
    }
    static object CloneConfiguration(object value, int depth)
    {
        if (depth > 20) throw new InvalidOperationException("Adapter configuration exceeds the source default merge depth (20).");
        value = NormalizeJsonValue(value);
        if (value is IDictionary dictionary) return MergeConfiguration(dictionary, null, depth);
        if (value is IList list) return list.Cast<object>().Select(item => CloneConfiguration(item, depth + 1)).ToList();
        return value;
    }
    static object NormalizeJsonValue(object value)
    {
        if (value is JObject obj)
        {
            var dictionary = Paths.NewDictionary();
            foreach (var property in obj.Properties()) dictionary[property.Name] = NormalizeJsonValue(property.Value);
            return dictionary;
        }
        if (value is JArray array) return array.Select(item => NormalizeJsonValue(item)).ToList();
        if (value is JValue scalar) return scalar.Value;
        return value;
    }
}
