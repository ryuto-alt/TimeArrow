// BackdropSky.hlsl -- 最奥の空壁(Backdrop)専用。ステージ別の自作空テクスチャ
// (tools/blender_bg/gen_sky.py 生成の bg_sky{n}.png)をアンリットで表示する。
// カメラ正対の法線は太陽とndotl=0になるため、ライティングすると環境光だけで
// くすむ(BackdropCollapse時代に踏んだバグ)。空は自発光=テクスチャ色そのまま。
// BGProp.lua が弓の構え中に effectValue=10 を送ってくるので、
// 青白い減彩で「時間が引き延ばされている」を空にも反復する。

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
    float4 color      : COLOR;
    float2 texCoord   : TEXCOORD0;
};

PSInput VSMain(VSInput input)
{
    PSInput output;
    output.positionSV = mul(float4(input.position, 1.0f), mvp);
    output.color      = input.color;
    output.texCoord   = input.texCoord;
    return output;
}

float Hash1(float p)
{
    return frac(sin(p * 127.1f) * 43758.5453f);
}
float Hash2(float2 p)
{
    return frac(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453f);
}

float4 PSMain(PSInput input) : SV_TARGET
{
    // 注意: boxのUVは v=1 が上(D3Dのv=0=画像先頭に合わせテクスチャは反転済み)。
    // つまり uv.y が大きいほど空の上=星の領域。地平はだいたい uv.y=0.2。
    float2 uv = input.texCoord;
    float3 sky = g_albedo.Sample(g_sampler, uv).rgb * input.color.rgb;

    // 星雲あたりがごくゆっくり明滅する呼吸(気付くか気付かないか程度)
    sky *= 1.0f + 0.03f * sin(time * 0.23f + uv.x * 6.0f);

    float aboveHorizon = smoothstep(0.26f, 0.40f, uv.y);

    // ── 瞬く星(テクスチャの星とは別に、シェーダー側でチラチラする層を重ねる) ──
    float2 sgrid = uv * float2(160.0f, 80.0f);
    float2 scell = floor(sgrid);
    float  srnd = Hash2(scell);
    if (srnd > 0.965f && aboveHorizon > 0.0f)
    {
        float2 sc = frac(sgrid) - 0.5f;
        float spot = saturate(1.0f - dot(sc, sc) * 9.0f);
        float tw = 0.35f + 0.65f * pow(saturate(sin(time * (1.5f + srnd * 3.0f) + srnd * 40.0f) * 0.5f + 0.5f), 3.0f);
        sky += float3(0.85f, 0.93f, 1.0f) * spot * tw * 0.65f * aboveHorizon;
    }

    // ── 流れ星: 数秒おきに1本、毎回違う場所から斜めに流れて燃え尽きる ──
    [unroll]
    for (int i = 0; i < 2; i++)
    {
        float period = 6.5f + i * 4.3f;
        float t = time / period + i * 0.53f;
        float id = floor(t) + i * 37.0f;
        float ph = frac(t);
        if (ph < 0.28f)   // 周期の前半だけ流れる(残りは夜空のまま)
        {
            float r0 = Hash1(id), r1 = Hash1(id + 0.7f);
            float2 head0 = float2(0.05f + 0.8f * r0, 0.98f - 0.25f * r1);
            float2 dir = normalize(float2(0.75f + 0.3f * r1, -0.45f - 0.25f * r0));
            float2 head = head0 + dir * (ph / 0.28f) * 0.55f;
            float2 rel = uv - head;
            float along = dot(rel, -dir);                 // 頭から尾へ
            float perp = abs(rel.x * dir.y - rel.y * dir.x);
            float tail = 0.10f + 0.06f * r1;
            if (along > 0.0f && along < tail)
            {
                float body = (1.0f - along / tail);       // 尾に向かって減衰
                float core = exp(-perp * perp * 300000.0f * (1.0f + along * 30.0f));
                float fade = sin(saturate(ph / 0.28f) * 3.14159f);   // 出現→燃え尽き
                sky += float3(1.0f, 0.95f, 0.8f) * body * body * core * fade * 1.5f * aboveHorizon;
            }
        }
    }

    // スローモーション(弓の構え中): 青白く減彩
    if (effectValue >= 10.0f)
    {
        float g = dot(sky, float3(0.299f, 0.587f, 0.114f));
        sky = lerp(sky, float3(g * 0.8f, g * 0.95f, g * 1.25f), 0.5f);
    }
    return float4(sky, 1.0f);
}
