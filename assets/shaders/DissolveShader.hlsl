// カスタムシェーダー: 左から正方形セル単位で崩壊するディゾルブ
// エンジンの共有 RootSignature(b0=PerObject, b1=PerFrame の先頭部分, t0+s0=アルベド)に合わせてあります。
// 自由に書き換えてOK。保存すると自動でホットリロードされます。

Texture2D    g_albedo  : register(t0);
SamplerState g_sampler : register(s0);

// PerObject constants (b0) - MVP + Model
cbuffer PerObjectConstants : register(b0)
{
    float4x4 mvp;
    float4x4 model;
};

// PerFrame constants (b1) - 先頭部分だけ宣言(shaders/forward/Lighting.hlsli と同一オフセット厳守)
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

/// 頂点をクリップ空間へ変換し、ピクセルシェーダーへ描画情報を渡します。
PSInput VSMain(VSInput input)
{
    PSInput output;
    output.positionSV  = mul(float4(input.position, 1.0f), mvp);
    output.worldNormal = normalize(mul(input.normal, (float3x3)model));
    output.color        = input.color;
    output.texCoord      = input.texCoord;
    return output;
}

/// 2次元の整数座標から、セルごとに安定した疑似乱数を生成します。
float RandomCell(float2 cell)
{
    float3 p = frac(float3(cell.xyx) * 0.1031f);
    p += dot(p, p.yzx + 33.33f);
    return frac((p.x + p.y) * p.z);
}

/// 左から右へ進む崩壊量を、演出の待機時間を含めて生成します。
float GetDissolveProgress(float currentTime)
{
    static const float DISSOLVE_DURATION = 4.0f;
    static const float HOLD_DURATION = 1.0f;
    static const float CYCLE_DURATION = DISSOLVE_DURATION + HOLD_DURATION;

    // 完全な形を一度見せてから、一定速度で崩壊を進めます。
    float cycleTime = fmod(max(currentTime, 0.0f), CYCLE_DURATION);
    return saturate((cycleTime - HOLD_DURATION) / DISSOLVE_DURATION);
}

/// 正方形セルごとのランダムな順序を使い、左から進む崩壊マスクを返します。
float GetDissolveMask(float2 uv, float progress)
{
    static const float GRID_SIZE = 128.0f;
    static const float RANDOM_WIDTH = 0.075f;

    float2 cell = min(floor(saturate(uv) * GRID_SIZE), GRID_SIZE - 1.0f);
    float randomOffset = (RandomCell(cell) - 0.5f) * RANDOM_WIDTH;

    // 進行境界付近のセルだけをランダム化し、全体の向きは左から右に保ちます。
    float collapseThreshold = lerp(-RANDOM_WIDTH, 1.0f + RANDOM_WIDTH, progress);
    float cellOrder = (cell.x + 0.5f) / GRID_SIZE + randomOffset;
    return step(collapseThreshold, cellOrder);
}

/// アルベドとランバート照明を適用し、崩壊済みの正方形セルを破棄します。
float4 PSMain(PSInput input) : SV_TARGET
{
    float4 albedo = g_albedo.Sample(g_sampler, input.texCoord) * input.color;

    float progress = GetDissolveProgress(time * 0.25f);
    float dissolveMask = GetDissolveMask(input.texCoord, progress);
    clip(min(dissolveMask, albedo.a) - 0.001f);

    float3 N = normalize(input.worldNormal);
    float3 L = normalize(-lightDir);
    float  ndotl = max(dot(N, L), 0.0f);

    float3 color = albedo.rgb * (lightColor * ndotl + ambientStrength);
    return float4(color * 8, albedo.a);
}
