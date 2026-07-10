// dissolve.hlsl -- Sprite2D 用カスタムシェーダー(worldSpaceのみ)。矢で先送りされたオブジェクトが
// 一瞬フェーズアウトして消える瞬間を、疑似ノイズで溶けるように見せる。CrushWall.lua が
// scene:setSpriteEffect(e, 0..1) で effectValue(=消滅の進捗)を送ってくる。0=通常表示、1=完全に消える。
// 契約はメッシュ用カスタムシェーダーと異なる(docs/AUTHORING.md §6.1):
//   cbuffer b0 = float4x4 gTransform(viewProj、頂点は既にワールド座標) + float gTime
//   頂点 = POSITION/TEXCOORD0/COLOR0/TEXCOORD1(effect)、エントリポイントはVSMain/PSMain固定。

cbuffer SpriteCB : register(b0)
{
    float4x4 gTransform;
    float    gTime;
};

struct VSIn
{
    float3 pos    : POSITION;
    float2 uv     : TEXCOORD0;
    float4 col    : COLOR0;
    float  effect : TEXCOORD1;
};

struct PSIn
{
    float4 pos    : SV_POSITION;
    float2 uv     : TEXCOORD0;
    float4 col    : COLOR0;
    float  effect : TEXCOORD1;
};

Texture2D    gTex  : register(t0);
SamplerState gSamp : register(s0);

PSIn VSMain(VSIn v)
{
    PSIn o;

    // 消滅の途中(effect が 0 でも 1 でもない)だけ小さく揺らす。溶けかけの不安定さを表現する。
    float wobbleAmt = v.effect * (1.0f - v.effect) * 4.0f;  // effect=0.5 でピーク、0/1で0
    float3 pos = v.pos;
    pos.x += sin(gTime * 22.0f + v.uv.y * 9.0f) * 0.05f * wobbleAmt;
    pos.y += cos(gTime * 17.0f + v.uv.x * 9.0f) * 0.03f * wobbleAmt;

    o.pos    = mul(float4(pos, 1.0f), gTransform);
    o.uv     = v.uv;
    o.col    = v.col;
    o.effect = v.effect;
    return o;
}

// 0..1 の疑似乱数(uv + time base)。gTime を混ぜているので同じ effect 値でも模様がわずかに揺らぐ。
float Noise(float2 uv, float t)
{
    return frac(sin(dot(uv * 43.0f + t * 0.25f, float2(12.9898f, 78.233f))) * 43758.5453f);
}

float4 PSMain(PSIn p) : SV_TARGET
{
    float4 tex = gTex.Sample(gSamp, p.uv) * p.col;

    float dissolve = saturate(p.effect);
    float n = Noise(p.uv, gTime);

    // ノイズ値がdissolve未満の画素は消える(ノイズで食われたように欠けていく)。
    if (n < dissolve)
        discard;

    // 消える境界のすぐ内側だけ発光させる(溶ける縁が光る演出)。
    float rim = 1.0f - saturate((n - dissolve) / 0.12f);
    float3 glowColor = float3(0.4f, 0.85f, 1.0f);
    float3 outColor = tex.rgb + glowColor * rim * rim * 2.5f;

    return float4(outColor, tex.a);
}
