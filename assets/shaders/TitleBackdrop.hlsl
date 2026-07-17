// TitleBackdrop.hlsl -- タイトル背景パネル。ネイビー基調にロゴ裏のハロと斜めシマー。
// BGM(128BPM)同期: title.lua が setMeshEffect で「拍数(小数)」を effectValue に毎フレーム
// 渡してくる。拍頭で明るく灯って減衰するパルス+小節頭(4拍)の強アクセント。
// effectValue が 0 のとき(エディタ編集中など)は time から 128BPM 相当を自走する。

Texture2D    g_albedo  : register(t0);
SamplerState g_sampler : register(s0);

cbuffer PerObjectConstants : register(b0)
{
    float4x4 mvp;
    float4x4 model;
    float    effectValue;
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

    // 拍位相: Luaから拍数が来ればそれを、無ければtimeから128BPM相当を自走
    float beats  = (effectValue > 0.0001f) ? effectValue : time * 2.133333f;
    float pulse  = exp(-frac(beats) * 5.0f);          // 拍頭で灯って減衰
    float accent = exp(-frac(beats * 0.25f) * 10.0f); // 小節頭(4拍ごと)は強め

    // ロゴ(-10, 4.1)裏のほのかな青ハロ(拍で息づく)
    float2 dv = (wp - float2(-10.0f, 4.1f)) * float2(0.45f, 1.0f);
    float halo = exp(-dot(dv, dv) * 0.015f);
    float3 haloCol = float3(0.05f, 0.09f, 0.18f) * halo * (0.75f + 0.35f * pulse + 0.25f * accent);

    // 斜めシマー: 16拍で1周期ぶん流れ、拍頭で明るく瞬く
    float s = sin((wp.x + wp.y) * 0.5f - beats * 0.3927f) * 0.5f + 0.5f;
    s = pow(s, 6.0f);
    float3 shimmer = float3(0.02f, 0.045f, 0.08f) * s * (0.55f + 1.1f * pulse + 0.6f * accent);

    // 拍頭は全体もわずかに持ち上げる
    float3 beatLift = float3(0.006f, 0.010f, 0.018f) * pulse + float3(0.004f, 0.007f, 0.014f) * accent;

    // 下端をさらに沈める
    float sink = saturate((wp.y + 3.0f) * 0.12f);
    float3 result = (base + haloCol + shimmer + beatLift) * (0.55f + 0.45f * sink);
    return float4(result, input.color.a);
}
