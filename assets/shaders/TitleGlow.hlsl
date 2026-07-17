// TitleGlow.hlsl -- タイトルロゴ文字/弓用の発光シェーダー(BGM 128BPM同期)。
// 頂点色基調 + 上下グラデ + リム + シャインスイープ(8拍で1往走) + 拍頭パルス。
// effectValue=拍数(TitleLogoIntro.luaが供給)。0のときはtimeから自走。

Texture2D    g_albedo  : register(t0);
SamplerState g_sampler : register(s0);

cbuffer PerObjectConstants : register(b0)
{
    float4x4 mvp;
    float4x4 model;
    float    effectValue;   // Luaから毎フレーム渡される「拍数(小数)」
    float3   _pad;
    float4   shaderParams;  // x: 演出強度(0..1, サビで1)
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

    float beats = (effectValue > 0.0001f) ? effectValue : time * 2.133333f;
    float pulse = exp(-frac(beats) * 5.0f);

    // 輝き(0=未点灯:発光・スイープ無し / 1=サビ後フル)。エディタでは0.8で自走
    float brill = shaderParams.x;
    if (effectValue <= 0.0001f && brill <= 0.0001f) brill = 0.8f;

    float grad = saturate((input.worldPos.y - 2.9f) * 0.42f);
    float facing = saturate(-N.z);
    float3 body = base * (0.52f + 0.38f * grad) * (0.3f + 0.75f * facing) * (0.9f + 0.5f * brill);

    // リム: ベース色由来(氷文字=シアン白/金の矢=ゴールド)
    float rim = pow(1.0f - abs(N.z), 3.0f);
    float3 rimCol = base * 1.6f + 0.15f;
    float3 rimGlow = rimCol * rim * (0.15f + (0.55f + 0.35f * pulse) * brill);

    // シャインスイープ: 8拍で左→右(点灯後のみ)
    float sweepPos = frac(beats / 8.0f) * 2.2f - 0.6f;
    float x01 = saturate((input.worldPos.x + 17.5f) / 15.5f);
    float d = (x01 - sweepPos) - (input.worldPos.y - 4.0f) * 0.06f;
    float sweep = exp(-d * d * 260.0f);
    float3 sweepGlow = float3(1.3f, 1.4f, 1.5f) * sweep * brill;

    float3 result = (body + rimGlow + sweepGlow) * (1.0f + 0.10f * pulse * brill);
    return float4(result, input.color.a);
}
