// IntroGlow.hlsl -- 開幕シネマの3D文字/ボード(Intro_*)専用シェーダー。
// 画面全体を暗転オーバーレイで沈めている間も演出モデルだけは主役として光るよう、
// ライティングを無視した自発光ベース + 流れる金のきらめき + 疑似リムライト。
// StageIntro.lua が scene:setMeshEffect で送るフラッシュ量(0=通常/スラム直後~2.2)を
// effectValue で受けて、着弾の瞬間に白金に発光する。
Texture2D    g_albedo  : register(t0);
SamplerState g_sampler : register(s0);

cbuffer PerObjectConstants : register(b0)
{
    float4x4 mvp;
    float4x4 model;
    float    effectValue;
    float4   shaderParams;
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
    float4 wp = mul(float4(input.position, 1.0f), model);
    output.positionSV  = mul(float4(input.position, 1.0f), mvp);
    output.worldNormal = normalize(mul(input.normal, (float3x3)model));
    output.color       = input.color;
    output.texCoord    = input.texCoord;
    output.worldPos    = wp.xyz;
    return output;
}

float4 PSMain(PSInput input) : SV_TARGET
{
    float4 albedo = g_albedo.Sample(g_sampler, input.texCoord) * input.color;
    float3 N = normalize(input.worldNormal);

    // 自発光ベース(暗転オーバーレイ越しでもしっかり明るい)+立体感の薄い陰影
    float shade = 0.88f + 0.18f * saturate(N.y) + 0.10f * saturate(-N.z);
    float3 result = albedo.rgb * 1.35f * shade;

    // 流れる金のきらめき(ワールド座標を斜めに走る帯)
    float band = sin(input.worldPos.x * 1.6f + input.worldPos.y * 1.1f - time * 5.0f);
    float shimmer = pow(saturate(band * 0.5f + 0.5f), 6.0f);
    result += float3(1.0f, 0.85f, 0.45f) * shimmer * 0.55f;

    // 疑似リムライト(輪郭が金色に縁取られて背景から浮く)
    float rim = pow(1.0f - abs(N.z), 2.5f);
    result += float3(1.0f, 0.8f, 0.4f) * rim * 0.4f;

    // スラム直後のフラッシュ(StageIntro.lua が setMeshEffect で送る 0..2.2)
    result += float3(1.0f, 0.96f, 0.8f) * saturate(effectValue) * 0.9f
            + float3(1.0f, 1.0f, 1.0f) * saturate(effectValue - 1.0f) * 0.8f;

    return float4(result, albedo.a);
}