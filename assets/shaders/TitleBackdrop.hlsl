// TitleBackdrop.hlsl -- タイトル背景。BGM(128BPM)同期の明滅。
// effectValue=拍数(title.luaが供給)、shaderParams.x=演出強度(TitleLogoIntro.luaが供給。
// イントロ中0.25、サビ(7.72s)で1.0)。どちらも0なら編集ビュー用に自走/中間強度。

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
    float3 base = float3(0.035f, 0.05f, 0.10f);
    float2 wp = input.worldPos.xy;

    float beats  = (effectValue > 0.0001f) ? effectValue : time * 2.133333f;
    // inten=0なら拍点滅は完全停止(サビ前)。エディタ(Lua無し)では0.6で自走
    float inten  = shaderParams.x;
    if (effectValue <= 0.0001f && inten <= 0.0001f) inten = 0.6f;
    float amp    = 1.15f * inten;

    float pulse  = exp(-frac(beats) * 5.0f) * amp;
    float accent = exp(-frac(beats * 0.25f) * 10.0f) * amp;

    // ロゴ裏ハロ(拍で息づく)
    float2 dv = (wp - float2(-10.0f, 4.1f)) * float2(0.45f, 1.0f);
    float halo = exp(-dot(dv, dv) * 0.015f);
    float3 haloCol = float3(0.05f, 0.09f, 0.18f) * halo * (0.7f + 0.5f * pulse + 0.35f * accent);

    // 斜めシマー: 16拍で1波長流れ、拍頭で瞬く
    float s = sin((wp.x + wp.y) * 0.5f - beats * 0.3927f) * 0.5f + 0.5f;
    s = pow(s, 6.0f);
    float3 shimmer = float3(0.02f, 0.045f, 0.08f) * s * (0.45f + 1.4f * pulse + 0.8f * accent);

    // 拍頭の全体リフト
    float3 beatLift = float3(0.006f, 0.010f, 0.018f) * pulse + float3(0.005f, 0.008f, 0.016f) * accent;

    float sink = saturate((wp.y + 3.0f) * 0.12f);
    float3 result = (base + haloCol + shimmer + beatLift) * (0.55f + 0.45f * sink);
    // サビ頭の画面フラッシュ「ぴか!」(params.y: 1→0減衰をLuaが送る)
    result += float3(0.70f, 0.82f, 1.0f) * shaderParams.y;
    return float4(result, input.color.a);
}
