// arrow.hlsl -- 時間スキップ矢(Arrowエンティティ)専用の自己発光パルスシェーダー。
// scene:setColor() で入れた頂点カラー(先送り=シアン/巻き戻し=橙、Player.luaのDIR_COLOR)を
// 基調に time でサイン波の発光パルスを重ねる。色の切り替えはLua側(setColor)任せで、
// このシェーダー自体は先送り/巻き戻しの区別を一切知らない。

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
    float pulse = 0.6f + 0.4f * sin(time * 8.0f);
    float3 glow = input.color.rgb * (1.2f + pulse * 1.8f);  // ベース色より明るく発光(HDRブルーム対応)
    return float4(glow, input.color.a);
}
