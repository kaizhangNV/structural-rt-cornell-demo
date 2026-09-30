module module_generic_trace_helper;

// A real imported module dispatches through a generic interface requirement.
public interface ITracer
{
    uint traceValue();
}

public uint traceViaInterface<T : ITracer>(T tracer)
{
    return tracer.traceValue();
}
