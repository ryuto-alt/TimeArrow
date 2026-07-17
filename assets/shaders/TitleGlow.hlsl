// TitleGlow.hlsl -- タイトルロゴ文字用の発光シェーダー。
// 頂点カラー(JSONのcolor)基調 + 上下グラデ + 輪郭リム + 周期シャインスイープ。
// タイトルカメラは+Z正対固定なので視線方向は(0,0,1)近似。

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
    float3 base = input.color.rgb;
    float3 N = normalize(input.worldNormal);

    // 上下グラデ(上端ほど明るい)
    float grad = saturate((input.worldPos.y - 2.9f) * 0.42f);
    // 立体感: 正面がいちばん明るく側面は締める
    float facing = saturate(-N.z);
    float3 body = base * (0.52f + 0.38f * grad) * (0.3f + 0.75f * facing);

    // リム: 輪郭を冷光で細く縁取り
    float rim = pow(1.0f - abs(N.z), 3.0f);
    float3 rimGlow = float3(0.4f, 0.85f, 1.25f) * rim * 0.55f;

    // シャインスイープ: 約3.6秒周期で左->右へ細い光帯
    float sweepPos = frac(time / 3.6f) * 2.2f - 0.6f;
    float x01 = saturate((input.worldPos.x + 17.5f) / 15.5f);
    float d = (x01 - sweepPos) - (input.worldPos.y - 4.0f) * 0.06f;
    float sweep = exp(-d * d * 260.0f);
    float3 sweepGlow = float3(1.3f, 1.4f, 1.5f) * sweep;

    float pulse = 1.0f + 0.04f * sin(time * 2.2f);
    float3 result = (body + rimGlow + sweepGlow) * pulse;
    return float4(result, input.color.a);
}
