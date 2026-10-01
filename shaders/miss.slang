implementing rt_pipeline;

public struct PrimaryMiss : rt::IMissShader
{
    typealias Context = PrimaryMissContext;

    void invoke(rt::MissInput<Context> input)
    {
        input.payload.hit = 0;
    }
}

public struct ShadowMiss : rt::IMissShader
{
    typealias Context = ShadowMissContext;

    void invoke(rt::MissInput<Context> input)
    {
        input.payload.occluded = 0;
    }
}
