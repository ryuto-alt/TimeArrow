// BackdropCollapse.hlsl -- Backdrop(奥の壁)用カスタムシェーダー。backdrop.hlsl と同じ
// ランバートライティング+マテリアルテクスチャはそのまま維持しつつ、残り時間の経過割合に応じて
// 正方形セル単位で左からランダムに崩壊させる(discard)。
// BackgroundCollapse.lua が scene:setMeshEffect(self, intensity) で
// PerObjectConstants.effectValue(0=無傷 / 1=全崩壊)を毎フレーム送ってくる
// (docs/AUTHORING.md §6「進捗/強度値を渡したい場合」のメッシュ用カスタムシェーダー機能)。

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

// 2次元の整数セル座標から、セルごとに安定した疑似乱数を生成する。
float RandomCell(float2 cell)
{
    float3 p = frac(float3(cell.xyx) * 0.1031f);
    p += dot(p, p.yzx + 33.33f);
    return frac((p.x + p.y) * p.z);
}

float4 PSMain(PSInput input) : SV_TARGET
{
    static const float GRID_SIZE = 16.0f;
    static const float RANDOM_WIDTH = 0.08f;

    // 正方形セルごとにランダムな順序を割り当て、左から右へ進む崩壊境界でクリップする。
    float2 cell = min(floor(saturate(input.texCoord) * GRID_SIZE), GRID_SIZE - 1.0f);
    float randomOffset = (RandomCell(cell) - 0.5f) * RANDOM_WIDTH;
    float cellOrder = (cell.x + 0.5f) / GRID_SIZE + randomOffset;
    // effectValue >= 10 はスローモーションフラグ(弓の構え中)。実際の崩壊割合は -10 して取り出す
    bool slowMo = effectValue >= 10.0f;
    float rawValue = slowMo ? (effectValue - 10.0f) : effectValue;

    // イージング(ease-out): 序盤から見た目にわかりやすく崩れるように、経過割合を前倒しする。
    float linearProgress = saturate(rawValue);
    float progress = 1.0f - (1.0f - linearProgress) * (1.0f - linearProgress);
    float collapseThreshold = lerp(-RANDOM_WIDTH, 1.0f + RANDOM_WIDTH, progress);

    if (cellOrder < collapseThreshold)
        discard;

    float4 albedo = g_albedo.Sample(g_sampler, input.texCoord) * input.color;

    float3 N = normalize(input.worldNormal);
    float3 L = normalize(-lightDir);
    float  ndotl = max(dot(N, L), 0.0f);
    float3 lit = albedo.rgb * (lightColor * ndotl + ambientStrength);

    // 斜めに緩やかに流れる細い発光ライン(backdrop.hlsl と同じ「時計の目盛」演出)
    float diag = input.texCoord.x * 6.0f + input.texCoord.y * 2.0f - time * 0.15f;
    float stripe = saturate(sin(diag * 6.2831853f) * 0.5f + 0.5f);
    stripe = pow(stripe, 8.0f);
    float3 glowColor = float3(0.35f, 0.75f, 1.0f);

    // 崩壊境界のすぐ内側だけオレンジで発光させる(崩れる縁が光る演出)。
    float edge = saturate((cellOrder - collapseThreshold) / 0.06f);
    float rimGlow = 1.0f - edge;
    float3 collapseGlow = float3(1.0f, 0.55f, 0.25f) * rimGlow * rimGlow * 1.8f;

    float3 result = lit + glowColor * stripe * 0.35f + collapseGlow;

    // スローモーション中: 青白く彩度を落とし、水平のタイムラインがゆっくり流れる
    // (時間が引き延ばされている感覚を画面全体の背景で伝える)
    if (slowMo)
    {
        float grey = dot(result, float3(0.299f, 0.587f, 0.114f));
        result = lerp(result, float3(grey * 0.8f, grey * 0.95f, grey * 1.25f), 0.55f);
        float streak = pow(saturate(sin((input.texCoord.y * 40.0f - time * 1.5f) * 6.2831853f) * 0.5f + 0.5f), 8.0f);
        result += float3(0.2f, 0.5f, 0.9f) * streak * 0.3f;
    }

    return float4(result, albedo.a);
}
