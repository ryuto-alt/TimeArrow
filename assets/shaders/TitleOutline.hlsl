// TitleOutline.hlsl -- タイトル文字の発光アウトライン用。文字メッシュを少し拡大して
// 背後(z+0.25)に重ね、無陰影の発光シルエットとして描く。params.x=輝き(文字と共有)。

Texture2D    g_albedo  : register(t0);
SamplerState g_sampler : register(s0);

cbuffer PerObjectConstants : register(b0)
{
    float4x4 mvp;
    float4x4 model;
    float    effectValue;
    float3   _pad;
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
};

PSInput VSMain(VSInput input)
{
    PSInput output;
    output.positionSV  = mul(float4(input.position, 1.0f), mvp);
    output.worldNormal = normalize(mul(input.normal, (float3x3)model));
    output.color       = input.color;
    output.texCoord    = input.texCoord;
    return output;
}

float4 PSMain(PSInput input) : SV_TARGET
{
    float beats = (effectValue > 0.0001f) ? effectValue : time * 2.133333f;
    float pulse = exp(-frac(beats) * 5.0f);
    float brill = shaderParams.x;
    if (effectValue <= 0.0001f && brill <= 0.0001f) brill = 0.8f;

    // 無陰影の発光シルエット。未点灯時は暗い縁取り(可読性用)、点灯後はネオン発光
    float3 result = input.color.rgb * (0.25f + (1.55f + 0.55f * pulse) * brill);
    return float4(result, input.color.a);
}
