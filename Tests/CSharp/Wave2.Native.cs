using System.Collections;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using SignalGraph;
using SovereignTrust.Foundation.Classes.Conduction;
using SovereignTrust.Foundation.Utilities.Conduction;
using SovereignTrust.Foundation.Wrappers.Adapters;
using SovereignTrust.Foundation.Classes.Adapters;

// Native component contracts; real storage acceptance remains the sole PS launcher.
public static class Wave2Suite
{
    sealed record Result(string Id, bool Pass, string? Error = null);
    static readonly List<Result> cases = new();
    static void Check(string id, Action assertion)
    {
        try { assertion(); cases.Add(new(id, true)); }
        catch (Exception error) { cases.Add(new(id, false, error.Message)); Console.Error.WriteLine($"ST_WAVE2_ASSERT: {id}: {error.Message}"); }
    }
    static void Require(bool condition, string message = "Contract assertion failed") { if (!condition) throw new InvalidOperationException(message); }
    static void Throws<T>(Action action) where T : Exception { try { action(); } catch (T) { return; } throw new InvalidOperationException("Expected " + typeof(T).Name); }
    static Signal S(object? value = null) { var signal = Signal.Start("Case"); signal.Result = value; return signal; }
    static AdapterDefinition Def(Func<object> factory, bool lazy = true) => new() { Family = "Storage", Factory = factory, Lazy = lazy };
    public sealed class Adapter : IAdapterInvoker
    {
        public static Adapter Start(NativeMappedFamily mapped, Conductor conductor) => new();
        public int ConstructCount, InvokeCount;
        public Signal Signal { get; } = S();
        public bool FailConstruct, ThrowConstruct, FailInvoke;
        public object? Configuration, Payload;
        public object?[]? Arguments;
        public Signal Construct(object configuration)
        {
            ConstructCount++; Configuration = configuration; Signal.SetJacketResult(configuration);
            if (ThrowConstruct) throw new InvalidOperationException("Construct failed");
            var signal = S(); if (FailConstruct) signal.LogMessage("Critical", "Construct failed"); return signal;
        }
        public Signal Invoke(string slot, string activity, Signal conductionSignal, object plan, Signal itemSignal)
        {
            InvokeCount++; Arguments = new object?[] { slot, activity, conductionSignal, plan, itemSignal };
            var signal = S(Payload ?? plan); if (FailInvoke) signal.LogMessage("Critical", "Provider failed"); return signal;
        }
    }
    public sealed class NoHook : IAdapterInvoker { public Signal Invoke(string s, string a, Signal c, object p, Signal i) => S(p); }
    public sealed class ThrowConstructor { public ThrowConstructor() => throw new InvalidOperationException("constructor failed"); }
    public sealed class WrongHook { public object Construct(object configuration) => new object(); }
    static object Identity(Assembly assembly) => new { Path = assembly.Location, Sha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(assembly.Location))), Identity = assembly.FullName, LoadContext = System.Runtime.Loader.AssemblyLoadContext.GetLoadContext(assembly)?.Name };
    static EnvironmentRuntime OwnedRuntime(Signal? parent = null)
    {
        var initialized = EnvironmentInitializer.InitializeRuntime(new Hashtable(), "owned-component-fixture", "ComponentFixture",
            _ => typeof(Adapter), null!, (configuration, _) => S(configuration), value => (IDictionary)(value is Signal signal ? signal.GetResult(true) : value), _ => S(), null!, null!, parent!);
        Require(!initialized.Failure(), "Native runtime fixture initialization failed");
        return (EnvironmentRuntime)initialized.Result;
    }
    static Hashtable Jacket(string family, string slot) => new() { ["VirtualPath"] = "SovereignTrust.Adapters." + family + ".Probe." + slot + ".Persistent.Read", ["FullType"] = "ComponentFixture.Adapter", ["Addresses"] = new[] { "owned" } };
    static void NativeOwnershipCases()
    {
        Check("native-initializer-creates-runtime-and-registration", () => {
            var r=OwnedRuntime(); var c=r.Conductor;
            Require(r.CreationOwner=="NativeEnvironmentInitializer" && c.NativeFamiliesInitialized && c.NativeRegistrationCount==37 && c.NativeConstructionCount==23 && c.FabRegistrationCount==1);
            Require(c.Slots.Count==25 && c.DispatchCount==0 && c.GetRegistration("Storage.Content").State==AdapterState.Registered);
            Require(ReferenceEquals(c.Signal.Pointer,c.Memory) && ReferenceEquals(r.ConductorSignal,c.Signal) && ReferenceEquals(r.BootstrapSignal.Jacket,c.Signal));
            Require(c.GetFamily("Condenser").Graph.Grid["FabCondenser"].Result is SovereignTrust.Foundation.Classes.Adapters.Condenser.FabCondenser);
        });
        Check("native-initializer-fresh-state-no-startup-effects", () => { var a=OwnedRuntime();var b=OwnedRuntime();Require(a.CreationIdentifier!=b.CreationIdentifier && !ReferenceEquals(a.Environment,b.Environment) && !ReferenceEquals(a.Conductor.Memory,b.Conductor.Memory) && a.Conductor.DispatchCount==0 && b.Conductor.DispatchCount==0); });
        Check("native-initializer-parent-exact-reference",()=>{var parent=S();var r=OwnedRuntime(parent);Require(ReferenceEquals(((Signal)r.EnvironmentSignal.ReversePointer).ReversePointer,parent));});
        var activities=new Dictionary<string,string>{{"Storage","Read"},{"Conduction","Invoke"},{"Data","Query"},{"Intelligence","SendMessage"},{"Network","ReadBatch"},{"Queue","PeekBatch"},{"Satellite","EmitSignal"},{"Session","RequestOrRegister"},{"Token","Get"},{"Utility","Inspect"}};
        foreach(var pair in activities)
        {
            var family=pair.Key;var activity=pair.Value;
            Check("native-family-leaf-route-"+family,()=>{
                var c=OwnedRuntime().Conductor;var context=S();var item=S();var plan=family=="Token" ? new Hashtable{{"Path","[Leaf.Tail/]"}} : new Hashtable{{"Container","bucket"},{"Resource","file"}};
                Require(!c.Fab.Register(Jacket(family,"Leaf"),context).Failure() && c.GetRegistration(family+".Leaf").State==AdapterState.Registered);
                var fullSlot=family is "Conduction" or "Data" or "Intelligence" or "Network" or "Queue" or "Satellite" or "Session" ? "Leaf.Tail" : "Leaf";
                var result=AdapterDispatcher.Invoke(c,family,fullSlot,activity,context,plan,item);
                var leaf=(Adapter)c.GetRegistration(family+".Leaf").Instance;
                Require(!result.Failure() && leaf.ConstructCount==1 && leaf.InvokeCount==1);
                if(family=="Token") Require(leaf.Arguments![0]==null && (string)leaf.Arguments[1]! == "Get" && (string)((IDictionary)leaf.Arguments[3]!)["Path"]! == "Leaf.Tail");
                else Require(ReferenceEquals(result.Result,plan) && (string)leaf.Arguments![0]! == fullSlot && ReferenceEquals(leaf.Arguments[3],plan));
                Require(ReferenceEquals(leaf.Arguments![2],context) && ReferenceEquals(leaf.Arguments[4],item));
                if(family is "Storage" or "Utility") Require((string)plan["VirtualPath"]! == "bucket/file");
                var missingPlan=family=="Token" ? new Hashtable{{"Path","Missing.Tail"}} : plan;
                Require(!AdapterDispatcher.Invoke(c,family,"missing",activity,context,missingPlan,item).Success() && leaf.InvokeCount==1);
            });
            Check("native-family-guard-before-leaf-effects-"+family,()=>{
                var c=OwnedRuntime().Conductor;var context=S();c.Fab.Register(Jacket(family,"Leaf"),context);
                var result=AdapterDispatcher.Invoke(c,family,"Leaf","UNKNOWN_ACTIVITY",context,new Hashtable(),S());
                Require(result.Failure() && c.GetRegistration(family+".Leaf").State==AdapterState.Registered && c.NativeConstructionCount==23 && c.DispatchCount==0);
            });
        }
        Check("native-condenser-slot-resolution",()=>{var c=OwnedRuntime().Conductor;var plan=new Hashtable();var r=AdapterDispatcher.Invoke(c,"condenser","Memory","gEnErAtE",S(),plan,S());var leaf=(Adapter)c.GetRegistration("Condenser.MemoryCondenser").Instance;Require(!r.Failure() && ReferenceEquals(r.Result,plan) && c.GetRegistration("Condenser.MemoryCondenser").State==AdapterState.Resolved && (string)leaf.Arguments![1]! == "gEnErAtE");});
        Check("native-source-activity-catalog",()=>{
            using var catalog=JsonDocument.Parse(File.ReadAllText(Path.Combine(Path.GetDirectoryName(typeof(Wave2Suite).Assembly.Location)!,"Wave2.MappedPolicies.json")));
            Require(catalog.RootElement.GetProperty("Schema").GetString()=="ST.Wave2.MappedPolicies/1");
            int families=0,activities=0;
            foreach(var row in catalog.RootElement.GetProperty("Families").EnumerateArray()){
                families++;var family=row.GetProperty("Family").GetString()!;Require(row.GetProperty("SourceSha256").GetString()!.Length==64);
                var c=OwnedRuntime().Conductor;c.Fab.Register(Jacket(family,"Leaf"),S());
                foreach(var entry in row.GetProperty("Activities").EnumerateArray()){
                    var activity=entry.GetString()!;activities++;var plan=family=="Token"?new Hashtable{{"Path","Leaf.Path"}}:new Hashtable{{"Container","bucket"},{"Resource","item"}};
                    Require(!AdapterDispatcher.Invoke(c,family.ToLowerInvariant(),"Leaf",activity.ToLowerInvariant(),S(),plan,S()).Failure(),family+"."+activity+" source activity rejected");
                    var observed=(Adapter)c.GetRegistration(family+".Leaf").Instance;
                    var expectedActivity=family is "Data" or "Intelligence" ? activity : family=="Token" ? "Get" : activity.ToLowerInvariant();
                    Require((string)observed.Arguments![1]! == expectedActivity,family+"."+activity+" forwarded activity spelling differs from source");
                }
                var leaf=(Adapter)c.GetRegistration(family+".Leaf").Instance;var before=leaf.InvokeCount;
                Require(AdapterDispatcher.Invoke(c,family,"Leaf","UnknownSourceActivity",S(),new Hashtable(),S()).Failure() && leaf.InvokeCount==before);
            }
            Require(families==10 && activities>50);
        });
        Check("native-fab-adapter-register-observe-and-unsupported",()=>{var c=OwnedRuntime().Conductor;var item=S();item.SetJacketResult(Jacket("Storage","Leaf"));var plan=new Hashtable();Require(!AdapterDispatcher.Invoke(c,"Condenser","Fab","Invoke",S(),plan,item).Failure());var observe=new Hashtable{{"Config",new Hashtable{{"Kind","Storage"},{"Slot","Leaf"},{"AbsentSlot","Absent"}}}};Require(!AdapterDispatcher.Invoke(c,"Condenser","Fab","ObserveMappedAdapter",S(),observe,S()).Failure() && c.FabObservationCount==1);Require(AdapterDispatcher.Invoke(c,"Condenser","Fab","Unknown",S(),plan,item).Failure() && c.FabRegistrationCount==2);});
        Check("native-reserved-distinct-empty-groups",()=>{var c=OwnedRuntime().Conductor;var conduit=(MappedConduitAdapter)c.GetFamily("Conduit");var quantum=(MappedQuantumAdapter)c.GetFamily("Quantum");Require(!conduit.SupportsFiveArguments && !quantum.SupportsFiveArguments && (object)conduit is not IAdapterInvoker && (object)quantum is not IAdapterInvoker);Require(conduit.Invoke(new object(),new object()).Success() && !conduit.Invoke(new object(),new object()).HasResult());Require(quantum.SubmitQuantumJob("circuit",new object()).Success() && !quantum.SubmitQuantumJob("circuit",new object()).HasResult());Require(AdapterDispatcher.Invoke(c,"Conduit","x","Invoke",S(),new object(),S()).Failure() && AdapterDispatcher.Invoke(c,"Quantum","x","SubmitQuantumJob",S(),new object(),S()).Failure() && c.DispatchCount==0);});
        Check("native-fab-observe-lazy-cache-source-identity",()=>{var c=OwnedRuntime().Conductor;var context=S();Require(!c.Fab.Register(Jacket("Storage","Leaf"),context).Failure());Require(c.NativeConstructionCount==23);var first=c.Fab.Observe("Storage","Leaf","Absent",context);Require(!first.Failure() && first.Result is FabObservation o && o.SourceMapping && o.MissingSlotAbsent && o.ModuleName=="ComponentFixture" && o.ClassName==nameof(Adapter) && o.MappedSlot=="Leaf" && o.RegistrationState=="Resolved");var leaf=c.GetRegistration("Storage.Leaf").Instance;Require(!c.Fab.Observe("Storage","Leaf","Absent",context).Failure() && ReferenceEquals(leaf,c.GetFamily("Storage").Graph.Grid["Leaf"].Result) && c.NativeConstructionCount==24 && c.FabObservationCount==2);});
        Check("native-fab-invalid-source-no-effects",()=>{var c=OwnedRuntime().Conductor;var mismatch=Jacket("Storage","Leaf");mismatch["Kind"]="Queue";Require(c.Fab.Register(mismatch,S()).Failure() && c.Fab.Register(Jacket("Unknown","Leaf"),S()).Failure() && c.Fab.Register(new Hashtable(),S()).Failure() && c.NativeConstructionCount==23 && c.FabRegistrationCount==1);});
        Check("native-fab-observation-negatives-no-construction",()=>{var c=OwnedRuntime().Conductor;c.Fab.Register(Jacket("Storage","Leaf"),S());Require(c.Fab.Observe("Storage","Leaf","Leaf",S()).Failure() && c.Fab.Observe("Storage","Missing","Absent",S()).Failure() && c.Fab.Observe("Unknown","Leaf","Absent",S()).Failure() && c.NativeConstructionCount==23);});
        Check("native-fab-eager-and-failed-type-resolution",()=>{var c=OwnedRuntime().Conductor;Require(!c.Fab.Register(Jacket("Storage","Leaf"),S(),false).Failure() && c.GetRegistration("Storage.Leaf").State==AdapterState.Resolved && c.NativeConstructionCount==24);var broken=new Conductor{MetadataConverter=value=>(IDictionary)value};broken.InitializeMappedAdapters(name=>name=="MISSING"?null!:typeof(Adapter),null!,(value,_)=>S(value));var j=Jacket("Storage","Broken");j["FullType"]="MISSING";Require(!broken.Fab.Register(j,S()).Failure() && broken.Fab.Observe("Storage","Broken","Absent",S()).Failure() && broken.GetRegistration("Storage.Broken").State==AdapterState.Failed);});
    }

    public static int Run(string receipt, bool deliberate = false)
    {
        cases.Clear();
        Check("native-type-family", () => { var c = new Conductor(); Require(c.Signal.GetType() == typeof(Signal) && c.Memory.GetType() == typeof(Graph)); Require(ReferenceEquals(c.Signal.Pointer, c.Memory)); });
        Check("forwarded-signal-type-identity", () => Require(typeof(Conductor).Assembly.GetType("SignalGraph.Signal", true) == typeof(Signal)));
        Check("adopt-shared-live-graph", () => { var s = S(); var g = s.CreateGraph(); var context = new object(); var c = Conductor.Adopt(s, context); Require(ReferenceEquals(c.Signal, s) && ReferenceEquals(c.Memory, g) && ReferenceEquals(c.Context, context)); });
        Check("adopt-rejects-missing-graph", () => Throws<ArgumentException>(() => Conductor.Adopt(S(), new object())));
        Check("missing-slot-fails", () => Require(new Conductor().Resolve("missing").Failure()));
        Check("invalid-registration-fails", () => Require(new Conductor().Register(" ", new AdapterDefinition()).Failure()));
        Check("unknown-type-factory-fails", () => { var c = new Conductor(); c.Register("x", new AdapterDefinition()); Require(c.Resolve("x").Failure() && c.GetRegistration("x").State == AdapterState.Failed); });
        Check("factory-null-fails", () => { var c = new Conductor(); c.Register("x", Def(() => null!)); Require(c.Resolve("x").Failure()); });
        Check("factory-throw-fails", () => { var c = new Conductor(); c.Register("x", Def(() => throw new InvalidOperationException("factory failed"))); Require(c.Resolve("x").Failure()); });
        Check("type-constructor-throw-fails", () => { var c = new Conductor(); c.Register("x", new AdapterDefinition { Type = typeof(ThrowConstructor) }); Require(c.Resolve("x").Failure()); });
        Check("type-construction-optional-hook", () => { var c = new Conductor(); c.Register("x", new AdapterDefinition { Type = typeof(NoHook) }); var r = c.Resolve("x"); Require(!r.Failure() && r.Result is NoHook); });
        Check("lazy-count-cache-identity", () => { int n = 0; var c = new Conductor(); c.Register("x", Def(() => { n++; return new Adapter(); })); Require(n == 0 && c.GetRegistration("x").State == AdapterState.Registered); var first = c.Resolve("x"); var again = c.Resolve("x"); Require(n == 1 && ReferenceEquals(first.Result, again.Result) && ((Adapter)first.Result).ConstructCount == 1); });
        Check("eager-count", () => { int n = 0; var c = new Conductor(); c.Register("x", Def(() => { n++; return new Adapter(); }, false)); Require(n == 1 && c.GetRegistration("x").State == AdapterState.Resolved); c.Resolve("x"); Require(n == 1); });
        Check("ready-instance-not-reconstructed", () => { var a = new Adapter(); var c = new Conductor(); c.Register("x", new AdapterDefinition { Instance = a }); Require(ReferenceEquals(c.Resolve("x").Result, a) && a.ConstructCount == 0); });
        Check("construct-failure-cached", () => { var c = new Conductor(); var a = new Adapter { FailConstruct = true }; c.Register("x", Def(() => a)); var failed = c.Resolve("x"); Require(failed.Failure() && ReferenceEquals(failed, c.Resolve("x")) && a.ConstructCount == 1); });
        Check("construct-throw-fails", () => { var c = new Conductor(); c.Register("x", Def(() => new Adapter { ThrowConstruct = true })); Require(c.Resolve("x").Failure()); });
        Check("construct-wrong-return-fails", () => { var c = new Conductor(); c.Register("x", Def(() => new WrongHook())); Require(c.Resolve("x").Failure()); });
        Check("hydration-failure-before-construct", () => { var c = new Conductor(); var a = new Adapter(); var d = Def(() => a); d.Hydrate = (_, _) => S().LogMessage("Critical", "hydrate failed"); c.Register("x", d); Require(c.Resolve("x").Failure() && a.ConstructCount == 0); });
        Check("hydration-null-fails", () => { var c = new Conductor(); var d = Def(() => new Adapter()); d.Hydrate = (_, _) => null!; c.Register("x", d); Require(c.Resolve("x").Failure()); });
        Check("stored-context-and-hydrated-reference", () => { var stored = new object(); var fallback = new object(); var hydrated = new Hashtable { ["Hydrated"] = true }; object? observed = null; var a = new Adapter(); var d = Def(() => a); d.Context = stored; d.Hydrate = (_, context) => { observed = context; return S(hydrated); }; var c = new Conductor(); c.Register("x", d); Require(!c.Resolve("x", fallback).Failure() && ReferenceEquals(observed, stored) && ReferenceEquals(a.Configuration, hydrated)); });
        Check("jacket-over-manifest-deep-merge", () => { var baseNested = new Hashtable { ["Keep"] = 1, ["Replace"] = 2 }; var a = new Adapter(); var d = Def(() => a); d.Manifest = new Hashtable { ["Nested"] = baseNested, ["RetainNullOverlay"] = "keep" }; d.Jacket = new Hashtable { ["Nested"] = new Hashtable { ["Replace"] = 3 }, ["RetainNullOverlay"] = null! }; var c = new Conductor(); c.Register("x", d); Require(!c.Resolve("x").Failure()); var config = (IDictionary)a.Configuration!; var nested = (IDictionary)config["Nested"]!; Require((int)nested["Keep"]! == 1 && (int)nested["Replace"]! == 3 && (string)config["RetainNullOverlay"]! == "keep" && (int)baseNested["Replace"]! == 2); });
        Check("configuration-canonical-reference-retained", () => { var shared = S(new object()); var a = new Adapter(); var d = Def(() => a); d.Manifest = new Hashtable { ["Shared"] = shared }; var c = new Conductor(); c.Register("x", d); c.Resolve("x"); Require(ReferenceEquals(((IDictionary)a.Configuration!)["Shared"], shared)); });
        Check("json-config-dictionary-list-merge", () => { var a = new Adapter(); var d = Def(() => a); d.Manifest = Newtonsoft.Json.Linq.JObject.Parse("{\"Rows\":[{\"Keep\":1},{\"Second\":true}]}"); d.Jacket = Newtonsoft.Json.Linq.JObject.Parse("{\"Rows\":[{\"Added\":2}]}"); var c = new Conductor(); c.Register("x", d); Require(!c.Resolve("x").Failure()); var rows = (IList)((IDictionary)a.Configuration!)["Rows"]!; Require(rows.Count == 2 && Convert.ToInt32(((IDictionary)rows[0]!)["Keep"]) == 1 && Convert.ToInt32(((IDictionary)rows[0]!)["Added"]) == 2 && (bool)((IDictionary)rows[1]!)["Second"]!); });
        Check("cached-factory-failure-identity", () => { int n = 0; var c = new Conductor(); c.Register("x", Def(() => { n++; throw new Exception("cached"); })); var first = c.Resolve("x"); Require(ReferenceEquals(first, c.Resolve("x")) && n == 1 && c.GetRegistration("x").Attempts == 1); });
        Check("retry-failed-resolution", () => { int n = 0; var c = new Conductor(); var d = Def(() => ++n == 1 ? throw new Exception("retry") : new NoHook()); d.RetryFailedResolution = true; c.Register("x", d); Require(c.Resolve("x").Failure() && !c.Resolve("x").Failure() && n == 2 && c.GetRegistration("x").State == AdapterState.Resolved); });
        Check("circular-resolution-fails", () => { var c = new Conductor(); c.Register("x", Def(() => { var recursive = c.Resolve("x"); if (recursive.Failure()) throw new Exception("circular"); return new NoHook(); })); Require(c.Resolve("x").Failure() && c.GetRegistration("x").State == AdapterState.Failed); });
        Check("duplicate-hard-preserves-registration", () => { var c = new Conductor(); c.Register("Slot", Def(() => new NoHook())); var first = c.GetRegistration("slot"); Require(c.Register("SLOT", Def(() => new Adapter())).Failure() && ReferenceEquals(first, c.GetRegistration("Slot")) && c.AdapterRegistry.Grid.Count == 1); });
        Check("duplicate-soft-warning", () => { var c = new Conductor(); c.Register("x", Def(() => new NoHook())); var r = c.Register("x", Def(() => new Adapter()), true); Require(!r.Failure() && r.Level == "Warning" && c.Slots.Count == 1); });
        Check("dispatch-five-argument-identity", () => { var c = new Conductor(); var a = new Adapter(); c.Register("Storage", new AdapterDefinition { Family = "Storage", Instance = a }); var conduction = S(); var item = S(); var plan = new object(); var r = AdapterDispatcher.Invoke(c, "Storage", "LocalContent", "Read", conduction, plan, item); Require(!r.Failure() && a.InvokeCount == 1 && (string)a.Arguments![0]! == (deliberate ? "DeliberatelyWrong" : "LocalContent") && (string)a.Arguments[1]! == "Read" && ReferenceEquals(a.Arguments[2], conduction) && ReferenceEquals(a.Arguments[3], plan) && ReferenceEquals(a.Arguments[4], item) && ReferenceEquals(r.Result, plan)); });
        Check("dispatch-native-false", () => { var c = new Conductor(); var a = new Adapter { Payload = false }; c.Register("Storage", new AdapterDefinition { Family = "Storage", Instance = a }); var r = AdapterDispatcher.Invoke(c, "Storage", "Local", "Exists", S(), new object(), S()); Require(!r.Failure() && r.Result is bool value && !value); });
        Check("failed-provider-propagation", () => { var c = new Conductor(); var a = new Adapter { FailInvoke = true }; c.Register("Storage", new AdapterDefinition { Family = "Storage", Instance = a }); Require(AdapterDispatcher.Invoke(c, "Storage", "Local", "Read", S(), new object(), S()).Failure() && a.InvokeCount == 1); });
        Check("failed-resolution-no-provider", () => { int calls = 0; var c = new Conductor(); c.Register("Storage", new AdapterDefinition { Family = "Storage", Factory = () => throw new Exception("no provider") }); Require(AdapterDispatcher.Invoke(c, "Storage", "Local", "Read", S(), new object(), S()).Failure() && calls == 0 && c.DispatchCount == 0); });
        Check("unsupported-family-no-provider", () => { var c = new Conductor(); Require(AdapterDispatcher.Invoke(c, "Conduit", "Local", "Read", S(), new object(), S()).Failure() && c.DispatchCount == 0); });
        Check("unsupported-storage-activity-no-provider", () => { var c = new Conductor(); var a = new Adapter(); c.Register("Storage", new AdapterDefinition { Family = "Storage", Instance = a }); Require(AdapterDispatcher.Invoke(c, "Storage", "Local", "Bogus", S(), new object(), S()).Failure() && a.InvokeCount == 0); });
        Check("route-family-mismatch-no-provider", () => { var c = new Conductor(); var a = new Adapter(); c.Register("Storage", new AdapterDefinition { Family = "Storage", Instance = a }); Require(AdapterDispatcher.Invoke(c, "Storage", "Local", "Read", S(), new object(), S(), "Network").Failure() && a.InvokeCount == 0); });
        Check("registration-family-mismatch-no-provider", () => { var c = new Conductor(); var a = new Adapter(); c.Register("Storage", new AdapterDefinition { Family = "Network", Instance = a }); Require(AdapterDispatcher.Invoke(c, "Storage", "Local", "Read", S(), new object(), S()).Failure() && a.InvokeCount == 0); });
        Check("missing-five-argument-contract-fails", () => { var c = new Conductor(); c.Register("Storage", new AdapterDefinition { Family = "Storage", Instance = new object() }); Require(AdapterDispatcher.Invoke(c, "Storage", "Local", "Read", S(), new object(), S()).Failure()); });
        Check("delegate-bridge-cache-owner", () => { var c = new Conductor(); var owner = new object(); var plan = new object(); int calls = 0; Func<string, string, Signal, object, Signal, Signal> callback = (_, _, _, p, _) => { calls++; return S(p); }; Require(!AdapterDispatcher.Bind(c, "Storage", owner, callback).Failure()); Require(!AdapterDispatcher.Bind(c, "Storage", owner, callback).Failure()); var r = AdapterDispatcher.Invoke(c, "Storage", "Local", "Read", S(), plan, S()); Require(!r.Failure() && calls == 1 && ReferenceEquals(r.Result, plan) && c.GetRegistration("Storage").Attempts == 1); Require(AdapterDispatcher.Bind(c, "Storage", new object(), callback).Failure()); });
        Check("delegate-throw-propagates", () => { var c = new Conductor(); AdapterDispatcher.Bind(c, "Storage", new object(), (_, _, _, _, _) => throw new Exception("callback")); Require(AdapterDispatcher.Invoke(c, "Storage", "Local", "Read", S(), new object(), S()).Failure()); });
        Check("delegate-null-return-fails", () => { var c = new Conductor(); AdapterDispatcher.Bind(c, "Storage", new object(), (_, _, _, _, _) => null!); Require(AdapterDispatcher.Invoke(c, "Storage", "Local", "Read", S(), new object(), S()).Failure()); });
        Check("fresh-environment-no-startup-effects", () => { const string json = "{\"Name\":\"Native\",\"Config\":{\"ContentRootPath\":\"owned\"}}"; var a = (EnvironmentRuntime)EnvironmentInitializer.Initialize(json).Result; var b = (EnvironmentRuntime)EnvironmentInitializer.Initialize(json).Result; Require(!ReferenceEquals(a.Environment, b.Environment) && !ReferenceEquals(a.Conductor.Memory, b.Conductor.Memory) && a.Conductor.Slots.Count == 0 && a.Conductor.DispatchCount == 0); });
        Check("invalid-environment-fails", () => Require(EnvironmentInitializer.Initialize("{}").Failure() && EnvironmentInitializer.Initialize("[]").Failure()));
        Check("conduit-lifecycle-context-feedback", () => { var conduit = new Conduit(); var context = new object(); var feedback = new Hashtable(); var conductor = new object(); var transient = new Hashtable(); var singleton = new Hashtable(); conduit.Context = context; conduit.Feedback = feedback; conduit.EngageConductor(conductor, transient, singleton); conduit.StartConduction(); Require(conduit.IsRunning); conduit.CompleteConduction(); Require(!conduit.IsRunning && ReferenceEquals(conduit.Conductor, conductor) && ReferenceEquals(conduit.Context, context) && ReferenceEquals(conduit.TransientTypeDictionary, transient) && ReferenceEquals(conduit.SingletonTypeDictionary, singleton) && (Guid)feedback["ConductionIdentifier"]! == conduit.ConduitIdentifier && feedback["ConductionDate"] is DateTime); });
        Check("conduit-not-running-phase-rejected", () => Throws<InvalidOperationException>(() => new Conduit().ExecutePhase(new object())));
        Check("conduit-running-phase-explicitly-unsupported", () => { var conduit = new Conduit(); conduit.StartConduction(); Throws<NotSupportedException>(() => conduit.ExecutePhase(new object())); });
        Check("conduit-missing-feedback-does-not-complete", () => { var conduit = new Conduit(); conduit.StartConduction(); Throws<InvalidOperationException>(() => conduit.CompleteConduction()); Require(conduit.IsRunning); });

        NativeOwnershipCases();
        int failed = cases.Count(item => !item.Pass);
        var report = new { Scope = "Wave2 native component contracts; no real storage claim", Command = Environment.GetCommandLineArgs(), PassCount = cases.Count - failed, FailCount = failed, SkipCount = 0, Total = cases.Count, DeliberateExpectation = deliberate, Cases = cases, TestAssembly = Identity(typeof(Wave2Suite).Assembly), CoreAssembly = Identity(typeof(Conductor).Assembly), SignalGraphAssembly = Identity(typeof(Signal).Assembly), NewtonsoftAssembly = Identity(typeof(Newtonsoft.Json.Linq.JObject).Assembly), Runtime = Environment.Version.ToString() };
        File.WriteAllText(receipt, JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine($"{cases.Count - failed}/{failed}/{cases.Count}, skip0");
        return failed == 0 ? 0 : 1;
    }
    public static int Main(string[] args)
    {
        string? receipt = null; bool deliberate = false;
        for (int i = 0; i < args.Length; i++) if (args[i] == "--receipt" && ++i < args.Length) receipt = args[i]; else if (args[i] == "--deliberate") deliberate = true; else throw new ArgumentException("Unknown Wave2 test argument");
        if (receipt == null || File.Exists(receipt)) throw new ArgumentException("A new --receipt path is required");
        return Run(receipt, deliberate);
    }
}
