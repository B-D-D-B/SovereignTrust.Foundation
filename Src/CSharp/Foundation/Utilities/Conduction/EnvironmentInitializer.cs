using System;
using System.Collections.Generic;
using System.Collections;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using SignalGraph;
using SovereignTrust.Foundation.Classes.Conduction;

namespace SovereignTrust.Foundation.Utilities.Conduction;

public sealed class EnvironmentRuntime
{
    public object Environment { get; internal set; }
    public Conductor Conductor { get; internal set; }
    public Signal ConductionSignal { get; internal set; }
    public Signal EnvironmentSignal { get; internal set; }
    public Signal ConductorSignal { get; internal set; }
    public Signal ConductorJacketSignal { get; internal set; }
    public Signal BootstrapSignal { get; internal set; }
    public string CreationOwner => "NativeEnvironmentInitializer";
    public Guid CreationIdentifier { get; } = Guid.NewGuid();
}

public static class EnvironmentInitializer
{
    public static Signal InitializeRuntime(object definition, string contentRoot, string moduleName, Func<string, Type> types, Func<object, string, string, Signal, object, Signal, Signal> invoke, Func<object, object, Signal> hydrate, Func<object, IDictionary> metadata, Func<EnvironmentRuntime, Signal> bootstrap, Action<object, string, object> writePlanMember = null, Func<object, string, object> readPlanMember = null, Signal parentSignal = null)
    {
        var op = Signal.Start("Initialize-STEnvironment", parentSignal);
        try
        {
            if (definition == null || string.IsNullOrWhiteSpace(contentRoot)) throw new ArgumentException("Environment Config.ContentRootPath is required.");
            var environment = Signal.Start("Environment", op); environment.SetJacketResult(definition); environment.CreateGraph();
            var conductor = new Conductor(definition) { BusinessModuleName = moduleName, MetadataConverter = metadata, PlanMemberWriter = writePlanMember, PlanMemberReader = readPlanMember };
            var bonding = Signal.Start("Start-BondingConduction", environment); conductor.Signal.Jacket = bonding;
            conductor.InitializeMappedAdapters(types, invoke, hydrate);
            var bootstrapSignal = Signal.Start("EmbeddedFabRequest", op); bootstrapSignal.Jacket = conductor.Signal;
            var jacket = Signal.Start("Conductor", environment); jacket.Jacket = conductor.Signal; jacket.Pointer = environment.Pointer;
            var conduction = Signal.Start("Conduction", op); conduction.Jacket = jacket; conduction.Control = jacket; conduction.Pointer = environment.Pointer;
            var runtime = new EnvironmentRuntime { Environment = definition, EnvironmentSignal = environment, Conductor = conductor, ConductorSignal = conductor.Signal, ConductorJacketSignal = jacket, ConductionSignal = conduction, BootstrapSignal = bootstrapSignal };
            var storage = Paths.NewDictionary(); storage["VirtualPath"] = "SovereignTrust.Adapters.Storage.EmbeddedFileSystem.Content.Persistent.Read"; storage["Addresses"] = new[] { contentRoot };
            var registered = conductor.Fab.Register(storage, bootstrapSignal, true, false);
            if (op.MergeSignalAndVerifyFailure(registered)) return op;
            if (bootstrap != null)
            {
                var initialized = bootstrap(runtime);
                if (initialized == null) throw new InvalidOperationException("Environment bootstrap returned no Signal.");
                if (op.MergeSignalAndVerifyFailure(initialized)) return op;
            }
            ((Graph)environment.Pointer).RegisterResultAsSignal("EnvironmentDetails", definition);
            op.Result = runtime;
        }
        catch (Exception error) { op.LogMessage("Critical", error.InnerException?.Message ?? error.Message, null, error); }
        return op;
    }
    public static string CloneEnvironmentJson(string environmentJson)
    {
        if (string.IsNullOrWhiteSpace(environmentJson)) throw new ArgumentException("Environment JSON is required.");
        var definition = JsonConvert.DeserializeObject<Dictionary<string, object>>(environmentJson)
            ?? throw new ArgumentException("Environment must be a JSON object.");
        return JsonConvert.SerializeObject(definition);
    }
    public static Signal Initialize(string environmentJson)
    {
        var op = Signal.Start("Initialize-STEnvironment");
        try
        {
            var clone = CloneEnvironmentJson(environmentJson);
            var root = JObject.Parse(clone);
            var config = root.GetValue("Config", StringComparison.OrdinalIgnoreCase) as JObject;
            if (string.IsNullOrWhiteSpace(config?.GetValue("ContentRootPath", StringComparison.OrdinalIgnoreCase)?.Value<string>()))
                throw new ArgumentException("Environment Config.ContentRootPath is required.");
            var definition = JsonConvert.DeserializeObject<Dictionary<string, object>>(clone);
            var conductor = new Conductor(definition);
            var conduction = Signal.Start("Conduction", op);
            conduction.Pointer = conductor.Memory;
            conduction.Jacket = conductor.Signal;
            conduction.Control = conductor.Signal;
            op.Result = new EnvironmentRuntime { Environment = definition, Conductor = conductor, ConductionSignal = conduction };
        }
        catch (Exception exception) { op.LogMessage("Critical", exception.Message, null, exception); }
        return op;
    }
}
