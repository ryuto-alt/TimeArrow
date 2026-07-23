// BackdropLayer.hlsl -- 背景装飾レイヤー(BG_*モデル)専用シェーダー。
// Blender自作モデルのベイク済みテクスチャを前提に:
//   RGB = アルベド / A = 発光マスク(時の結晶・砂・刻印など)
// をデコードし、奥行きに応じた大気フォグ + シルエット縁のシアンリム +
// 発光部の緩やかな脈動を乗せる。BGProp.lua が scene:setMeshEffect で
//   0..1 = 時間消滅の進行度(ステージ制限時間の全体でノイズセルが砕けて
//          消えていき、残り0秒で完全消滅) / +10 = スローモーション(弓の構え中)
// を送ってくる。スローモーション中は BackdropCollapse と同じ言語=
// 青白い減彩で「時間が引き延ばされている」を背景全体で反復する。
// 背景はゲーム面と見分けやすいよう全体を減光し、フォグも強めに寄せてある。

Texture2D    g_albedo  : register(t0);
SamplerState g_sampler : register(s0);

cbuffer PerObjectConstants : register(b0)
{
    float4x4 mvp;
    float4x4 model;
    float    effectValue;
    float4   shaderParams;   // xyz=フォグ色(ステージの空に合わせる。全0なら既定の青)
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
    float  viewDepth   : TEXCOORD2;
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
    output.viewDepth   = mul(wp, view).z;   // カメラからの奥行き(ゲーム面は約13)
    return output;
}

float RandomCell(float2 cell)
{
    float3 p = frac(float3(cell.xyx) * 0.1031f);
    p += dot(p, p.yzx + 33.33f);
    return frac((p.x + p.y) * p.z);
}

float4 PSMain(PSInput input) : SV_TARGET
{
    bool  slowMo   = effectValue >= 10.0f;
    float progress = saturate(slowMo ? (effectValue - 10.0f) : effectValue);

    // ── 時間消滅: ワールドXYノイズセルが進行度に応じて砕け落ちる(線形=残り時間と一致) ──
    static const float CELL = 0.45f;
    float2 cell = floor(input.worldPos.xy / CELL);
    float  cellRnd = RandomCell(cell);
    if (cellRnd < progress * 1.05f - 0.05f)
        discard;

    float4 tex = g_albedo.Sample(g_sampler, input.texCoord);
    float3 albedo = tex.rgb * input.color.rgb;
    float  glowMask = tex.a;      // ベイク時にαへ焼いた発光マスク

    float3 N = normalize(input.worldNormal);
    float3 L = normalize(-lightDir);
    float  ndotl = max(dot(N, L), 0.0f);
    // 背景は影側が潰れないようハーフランバート+底上げ環境光
    float  wrap = ndotl * 0.6f + 0.4f;
    float3 lit = albedo * (lightColor * wrap + ambientStrength * 0.8f);

    // シルエット縁のリム(カメラは常に-Z側から見る構図なので固定視線で近似)
    float rim = 1.0f - abs(dot(N, float3(0.0f, 0.0f, -1.0f)));
    lit += float3(0.24f, 0.55f, 0.75f) * pow(rim, 3.0f) * 0.20f;

    // 発光部: ゆっくり脈動(位置で位相をずらして群れ全体が同期しないように)
    float pulse = 0.7f + 0.3f * sin(time * 1.4f + input.worldPos.x * 0.35f + input.worldPos.y * 0.2f);
    float3 glow = tex.rgb * glowMask * pulse * 1.2f;

    // 大気フォグ+全体減光: 背景はゲーム面より一段沈めて見分けやすくする
    // フォグ色はステージの空に合わせて shaderParams.xyz で差し替え(全0なら既定の青)
    float3 fogColor = (dot(shaderParams.xyz, shaderParams.xyz) > 0.0001f)
                      ? shaderParams.xyz : float3(0.10f, 0.22f, 0.33f);
    float fog = saturate((input.viewDepth - 13.0f) / 8.0f) * 0.80f;
    lit = lerp(lit, fogColor, fog) * 0.80f;
    lit += glow * (1.0f - fog * 0.55f);   // 発光はフォグを少し貫いて残す

    // 砕ける直前のセルはシアンに光って予告する(時間に喰われていく感)
    if (progress > 0.001f)
    {
        float edge = saturate((cellRnd - (progress * 1.05f - 0.05f)) / 0.06f);
        lit += float3(0.35f, 0.8f, 1.0f) * (1.0f - edge) * 1.2f;
    }

    // スローモーション(弓の構え中): 青白く減彩=BackdropCollapseと同じ時間演出言語
    if (slowMo)
    {
        float g = dot(lit, float3(0.299f, 0.587f, 0.114f));
        float3 cold = lerp(float3(g, g, g), float3(0.55f, 0.75f, 1.0f) * g, 0.55f);
        lit = lerp(lit, cold, 0.6f);
    }

    return float4(lit, 1.0f);
}
