// backdrop.hlsl -- ステージ背景(Backdropエンティティ)に「時計の目盛/時の砂」風の
// 緩やかに流れる発光ラインを重ねるシェーダー。ベースの見た目(materialTextureOverridesの
// albedo)はステージごとに変えられるので、雰囲気の差別化はテクスチャ選択側で行い、
// このシェーダーは全ステージ共通の"時間が流れている感"のオーバーレイだけを担当する。

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
    float4 positionSV : SV_POSITION;
    float3 worldNormal : NORMAL;
    float4 color        : COLOR;
    float2 texCoord     : TEXCOORD0;
};

PSInput VSMain(VSInput input)
{
    PSInput output;
    output.positionSV  = mul(float4(input.position, 1.0f), mvp);
    output.worldNormal = normalize(mul(input.normal, (float3x3)model));
    output.color        = input.color;
    output.texCoord      = input.texCoord;
    return output;
}

float4 PSMain(PSInput input) : SV_TARGET
{
    float4 albedo = g_albedo.Sample(g_sampler, input.texCoord) * input.color;

    float3 N = normalize(input.worldNormal);
    float3 L = normalize(-lightDir);
    float  ndotl = max(dot(N, L), 0.0f);
    float3 lit = albedo.rgb * (lightColor * ndotl + ambientStrength);

    // 斜めに緩やかに流れる細い発光ライン(時計の目盛が流れていくイメージ)
    float diag = input.texCoord.x * 6.0f + input.texCoord.y * 2.0f - time * 0.15f;
    float stripe = saturate(sin(diag * 6.2831853f) * 0.5f + 0.5f);
    stripe = pow(stripe, 8.0f);  // 細く鋭いラインだけ残す

    float3 glowColor = float3(0.35f, 0.75f, 1.0f);
    float3 result = lit + glowColor * stripe * 0.35f;

    return float4(result, albedo.a);
}
