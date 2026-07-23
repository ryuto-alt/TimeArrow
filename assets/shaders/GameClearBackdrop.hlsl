// GameClearBackdrop.hlsl -- GAME CLEAR画面の祝祭背景。
// bg_game_clear.png(夕焼けの時計台レンダ)をベースに、
//   1. 全体の明度リフト(暗すぎたクリア画面を祝勝らしく明るく)
//   2. 時計中心から回転するゴッドレイ(金色。ゆっくり2系統を逆回転で重ねる)
//   3. 舞い散る紙吹雪(3層パララックス。金/シアン/マゼンタ/白、ひらひら回転)
//   4. きらめく星(ハッシュ配置+瞬き)
//   5. 時計中心の温かいハロ(ゆっくり呼吸)
// エンジンはリニア→sRGB変換するので加算レイヤーは小さめの値で設計する。
// smoothstep は必ず (lo, hi, x) の正順で書く(逆順は壊れる)。

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
    float4 positionSV : SV_POSITION;
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

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

// 紙吹雪1層: グリッドセルごとに1枚、落下+横揺れ+ひらひら(幅の明滅)する小さな矩形
float3 confettiLayer(float2 uv, float cells, float speed, float t)
{
    float2 gv = uv * cells;
    gv.y -= t * speed;                       // 落下(uvはy下向きなのでセル側を上へ流す)
    float2 id = floor(gv);
    float  rnd = hash21(id);
    float2 f = frac(gv) - 0.5;
    // セル内のランダム位置+横揺れ
    float2 center = (float2(rnd, hash21(id + 7.3)) - 0.5) * 0.6;
    center.x += sin(t * (1.0 + rnd) + rnd * 6.28) * 0.15;
    float2 d = f - center;
    // ひらひら: 回転しながら片軸が潰れる(紙が翻る見え方)
    float ang = t * (2.0 + rnd * 3.0) + rnd * 6.28;
    float2x2 rot = float2x2(cos(ang), -sin(ang), sin(ang), cos(ang));
    d = mul(rot, d);
    d.y /= max(0.25, abs(sin(t * (3.0 + rnd * 2.0) + rnd * 9.0)));
    float paper = (1.0 - smoothstep(0.030, 0.045, abs(d.x)))
                * (1.0 - smoothstep(0.055, 0.075, abs(d.y)));
    // 色はセルハッシュで4色から選ぶ
    float  c = frac(rnd * 4.0);
    float3 col = (c < 0.25) ? float3(1.0, 0.85, 0.35)
               : (c < 0.5)  ? float3(0.35, 0.9, 1.0)
               : (c < 0.75) ? float3(1.0, 0.45, 0.75)
                            : float3(1.0, 0.97, 0.9);
    return col * paper;
}

float4 PSMain(PSInput input) : SV_TARGET
{
    // box プリミティブの V は下原点なので反転(以降 uv は「y=0が画像の上」の画像空間)
    float2 uv = float2(input.texCoord.x, 1.0 - input.texCoord.y);
    float3 base = g_albedo.Sample(g_sampler, uv).rgb;

    // ── 1. 明度リフト: 全体を持ち上げ+シャドウを温かく起こす ──
    float3 col = base * 1.45;
    col += float3(0.10, 0.07, 0.03) * (1.0 - smoothstep(0.0, 0.45, dot(base, float3(0.33, 0.33, 0.33))));

    // 時計の中心(テクスチャ上おおよそ中央・上寄り)。アスペクト補正した座標系で放射系を作る
    float2 cc = float2(0.5, 0.27);
    float2 p = uv - cc;
    p.x *= 1.78;                             // 16:9 のアスペクト補正
    float r = length(p);
    float a = atan2(p.y, p.x);

    // ── 2. ゴッドレイ2系統(逆回転)。中心から出て遠くで減衰 ──
    float ray1 = pow(max(0.0, sin(a * 9.0 + time * 0.22)), 6.0);
    float ray2 = pow(max(0.0, sin(a * 5.0 - time * 0.15 + 1.7)), 8.0);
    float rayMask = smoothstep(0.06, 0.22, r) * (1.0 - smoothstep(0.35, 1.05, r));
    col += float3(1.0, 0.83, 0.45) * (ray1 * 0.075 + ray2 * 0.055) * rayMask;

    // ── 3. 紙吹雪(3層パララックス: 近いほど大きく速い) ──
    float3 confetti = confettiLayer(uv, 7.0, 0.55, time) * 0.85
                    + confettiLayer(uv + 3.7, 11.0, 0.80, time * 1.15) * 0.6
                    + confettiLayer(uv + 9.1, 16.0, 1.10, time * 1.3) * 0.4;
    col = lerp(col, confetti * 1.4, saturate(dot(confetti, float3(1, 1, 1)) * 0.9));

    // ── 4. きらめき: ハッシュ配置の星がランダム位相で瞬く ──
    float2 sgv = uv * 24.0;
    float2 sid = floor(sgv);
    float  srnd = hash21(sid + 31.7);
    float2 spos = frac(sgv) - 0.5 - (float2(srnd, hash21(sid + 55.1)) - 0.5) * 0.7;
    float  tw = pow(max(0.0, sin(time * (1.5 + srnd * 2.5) + srnd * 6.28)), 12.0);
    float  star = (1.0 - smoothstep(0.0, 0.05 + 0.04 * srnd, length(spos))) * tw;
    star *= step(0.55, srnd);                // 半分弱のセルにだけ星を置く(敷き詰めない)
    col += float3(1.0, 0.95, 0.8) * star * 0.35;

    // ── 5. 時計中心のハロ(ゆっくり呼吸) ──
    float breathe = 0.85 + 0.15 * sin(time * 0.8);
    col += float3(1.0, 0.8, 0.4) * (1.0 - smoothstep(0.0, 0.5, r)) * 0.10 * breathe;

    return float4(col, 1.0);
}
