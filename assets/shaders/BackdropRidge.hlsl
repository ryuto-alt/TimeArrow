// BackdropRidge.hlsl -- 2段背景の手前段=遠景の稜線帯(BG_Ridge_*モデル)専用。
// BackdropLayer.hlsl の大気表現(フォグ/リム/α発光マスク)に、
// BackdropCollapse.hlsl が担っていた「残り時間で左から崩壊」を
// **ワールド座標セル**で移植したもの(BlenderモデルのUVは島分割されていて
// texCoordセルでは空間的な崩壊順が作れないため)。崩れた穴からは奥の空壁が見える。
// BackgroundCollapse.lua が scene:setMeshEffect で送ってくる値:
//   0..1   = 崩壊進行度 / +10 = スローモーションフラグ(弓の構え中)

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
    output.viewDepth   = mul(wp, view).z;
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
    float rawValue = slowMo ? (effectValue - 10.0f) : effectValue;

    // ── ワールドXYセルで左から右へ崩壊(線形=残り時間と一致、0秒で完全消滅) ──
    // ステージ幅はまちまちなので X=-15..105 を崩壊レンジとして固定する
    // (稜線はどのステージでもこの範囲に収まるサイズで配置される)
    static const float CELL = 0.65f;          // セル一辺(ワールド単位)
    static const float RANDOM_WIDTH = 0.10f;
    float2 cell = floor(input.worldPos.xy / CELL);
    float randomOffset = (RandomCell(cell) - 0.5f) * RANDOM_WIDTH;
    float cellOrder = saturate((cell.x * CELL + 15.0f) / 120.0f) + randomOffset;

    float progress = saturate(rawValue);
    float collapseThreshold = lerp(-RANDOM_WIDTH, 1.0f + RANDOM_WIDTH, progress);
    if (cellOrder < collapseThreshold)
        discard;

    float4 tex = g_albedo.Sample(g_sampler, input.texCoord);
    float3 albedo = tex.rgb * input.color.rgb;    // input.color=ステージ別ティント
    float  glowMask = tex.a;

    float3 N = normalize(input.worldNormal);
    float3 L = normalize(-lightDir);
    float  wrap = max(dot(N, L), 0.0f) * 0.6f + 0.4f;
    float3 lit = albedo * (lightColor * wrap + ambientStrength * 0.8f);

    // シルエット縁のリム
    float rim = 1.0f - abs(dot(N, float3(0.0f, 0.0f, -1.0f)));
    lit += float3(0.24f, 0.55f, 0.75f) * pow(rim, 3.0f) * 0.28f;

    // 発光部(結晶/窓)の脈動
    float pulse = 0.7f + 0.3f * sin(time * 1.2f + input.worldPos.x * 0.3f);
    float3 glow = tex.rgb * glowMask * pulse * 1.6f;

    // 大気フォグ+減光: 稜線は空壁の手前=一番奥のシルエットとして強めに空へ溶かす
    float3 fogColor = (dot(shaderParams.xyz, shaderParams.xyz) > 0.0001f)
                      ? shaderParams.xyz : float3(0.10f, 0.22f, 0.33f);
    float fog = saturate((input.viewDepth - 15.0f) / 11.0f) * 0.84f;
    lit = lerp(lit, fogColor, fog) * 0.85f;
    lit += glow * (1.0f - fog * 0.55f);

    // 崩壊境界のすぐ内側をオレンジに光らせる(崩れていく縁)
    float edge = saturate((cellOrder - collapseThreshold) / 0.06f);
    float rimGlow = 1.0f - edge;
    lit += float3(1.0f, 0.55f, 0.25f) * rimGlow * rimGlow * 1.6f;

    // スローモーション: 青白く減彩
    if (slowMo)
    {
        float g = dot(lit, float3(0.299f, 0.587f, 0.114f));
        lit = lerp(lit, float3(g * 0.8f, g * 0.95f, g * 1.25f), 0.55f);
    }
    return float4(lit, 1.0f);
}
