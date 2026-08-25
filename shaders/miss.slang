implementing rt_pipeline;

public struct PrimaryMiss : rt::IMissShader<MissContext>
{
    void invoke(rt::MissInput<MissContext> input)
    {
        input.payload.hit = 0;
    }
}

public struct ShadowMiss : rt::IMissShader<MissContext>
{
    void invoke(rt::MissInput<MissContext> input)
    {
        input.payload.occluded = 0;
    }
}
