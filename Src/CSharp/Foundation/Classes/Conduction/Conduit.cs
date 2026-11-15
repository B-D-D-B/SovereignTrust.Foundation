using System;
using System.Collections;
using System.Collections.Generic;

namespace SovereignTrust.Foundation.Classes.Conduction;

public sealed class Conduit
{
    public Guid ConduitIdentifier { get; } = Guid.NewGuid();
    public string ConduitType { get; set; } = "Unspecified";
    public object Context { get; set; }
    public object Feedback { get; set; }
    public bool IsRunning { get; private set; }
    public IDictionary TransientTypeDictionary { get; private set; } = new Hashtable();
    public IDictionary SingletonTypeDictionary { get; private set; } = new Hashtable();
    public object ServiceContainer { get; set; }
    public object Conductor { get; private set; }
    public void EngageConductor(object conductor, IDictionary transientTypes, IDictionary singletonTypes)
    {
        Conductor = conductor;
        if (transientTypes != null) TransientTypeDictionary = transientTypes;
        if (singletonTypes != null) SingletonTypeDictionary = singletonTypes;
    }
    public void StartConduction() => IsRunning = true;
    public void ExecutePhase(object phase)
    {
        if (!IsRunning) throw new InvalidOperationException("Conduit is not running.");
        throw new NotSupportedException("Conduit.ExecutePhase is an unfinished source stub and has no native dispatch contract.");
    }
    public void CompleteConduction()
    {
        if (Feedback == null) throw new InvalidOperationException("Conduit feedback is required.");
        if (Feedback is IDictionary dictionary)
        {
            dictionary["ConductionIdentifier"] = ConduitIdentifier;
            dictionary["ConductionDate"] = DateTime.Now;
        }
        else if (Feedback != null)
        {
            var type = Feedback.GetType();
            var identifier = type.GetProperty("ConductionIdentifier");
            var date = type.GetProperty("ConductionDate");
            if (identifier == null || !identifier.CanWrite || date == null || !date.CanWrite)
                throw new InvalidOperationException("Conduit feedback must expose writable identifier and date.");
            identifier.SetValue(Feedback, ConduitIdentifier);
            date.SetValue(Feedback, DateTime.Now);
        }
        IsRunning = false;
    }
}
