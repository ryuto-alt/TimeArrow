// TitleBackdrop.hlsl -- タイトル背景パネル。ネイビー基調にロゴ裏のほのかなハロと
// ごく薄い斜めシマー(時の流れ)を重ねる。主張しすぎず文字を引き立てる係。

Texture2D    g_albedo  : register(t0);
SamplerState g_sampler : register(s0);

cbuffer PerObjectConstants : register(b0)
{
    float4x4 mvp;
    float4x4 model;
};

cbuffer PerFrameConstants : register(b1)
{
    float4x4 view;
    float4x4 proj;
    float3   lightDir;   float time;
    float3   lightColor; float ambientStrength;
};

struct VSInput
{
    float3 position    : POSITION;
    float3 normal      : NORMAL;
    float4 color       : COLOR;
    float2 texCoord    : TEXCOORD0;
    float4 tangent     : TANGENT;
    uint4  boneIndices : BLENDINDICES;
    float4 boneWeights : BLENDWEIGHT;
};

struct PSInput
{
    float4 positionSV  : SV_POSITION;
    float3 worldNormal : NORMAL;
    float4 color       : COLOR;
    float2 texCoord    : TEXCOORD0;
    float3 worldPos    : TEXCOORD1;
};

PSInput VSMain(VSInput input)
{
    PSInput output;
    output.positionSV  = mul(float4(input.position, 1.0f), mvp);
    output.worldNormal = normalize(mul(input.normal, (float3x3)model));
    output.color       = input.color;
    output.texCoord    = input.texCoord;
    output.worldPos    = mul(float4(input.position, 1.0f), model).xyz;
    return output;
}

float4 PSMain(PSInput input) : SV_TARGET
{
    // 頂点カラーはPlay/Stopの復元経路で失われることがあるため基調色は直書き
    float3 base = float3(0.035f, 0.05f, 0.10f);
    float2 wp = input.worldPos.xy;

    // ロゴ(-10, 4.1)裏のほのかな青ハロ
    float2 dv = (wp - float2(-10.0f, 4.1f)) * float2(0.45f, 1.0f);
    float halo = exp(-dot(dv, dv) * 0.015f);
    float3 haloCol = float3(0.05f, 0.09f, 0.18f) * halo;

    // ごく薄い斜めシマー(ゆっくり流れる)
    float s = sin((wp.x + wp.y) * 0.5f - time * 0.4f) * 0.5f + 0.5f;
    s = pow(s, 6.0f);
    float3 shimmer = float3(0.02f, 0.045f, 0.08f) * s;

    // 下端をさらに沈める
    float sink = saturate((wp.y + 3.0f) * 0.12f);
    float3 result = (base + haloCol + shimmer) * (0.55f + 0.45f * sink);
    return float4(result, input.color.a);
}
