// TitleBackdrop.hlsl -- タイトル背景「時空の射場」。BGM(128BPM)同期。
// effectValue=拍数(title.luaが供給)、shaderParams.x=演出強度(TitleLogoIntro.luaが供給。
// イントロ中0.25、サビ(7.72s)で1.0)、y=サビ頭フラッシュ(1→0減衰)。
// どちらも0なら編集ビュー用に自走/中間強度。
// レイヤ構成: 縦グラデ+FBM星雲 / 星空2層(回折スパイク+瞬き) / 流れ星10レーン /
//   ロゴ裏ハロ / 時計文字盤(60目盛+ドフィーヌ風時分針+1拍1ティックのクオーツ秒針。16拍1周=シークバーモチーフ) /
//   地平線グロー / ビネット / 拍リフト
// 星と流れ星は params.x にゲート = タイトル点灯(サビ)と同時に星空が開く

Texture2D    g_albedo  : register(t0);
SamplerState g_sampler : register(s0);

cbuffer PerObjectConstants : register(b0)
{
    float4x4 mvp;
    float4x4 model;
    float    effectValue;   // Luaから毎フレーム渡される「拍数(小数)」
    float3   _pad;
    float4   shaderParams;  // x: 演出強度(0..1) y: サビ頭フラッシュ
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

// ---- ノイズ ----------------------------------------------------------------
float hash21(float2 p)
{
    p = frac(p * float2(233.34f, 851.73f));
    p += dot(p, p + 23.45f);
    return frac(p.x * p.y);
}

float vnoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0f - 2.0f * f);
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float fbm(float2 p)
{
    float v = 0.0f, a = 0.5f;
    const float2x2 rot = float2x2(0.80f, 0.60f, -0.60f, 0.80f);  // 軸整列アーティファクト防止
    [unroll] for (int k = 0; k < 3; k++)
    {
        v += vnoise(p) * a;
        p = mul(rot, p) * 2.13f + 17.0f;
        a *= 0.5f;
    }
    return v;
}

float2x2 Rot(float a)
{
    float c = cos(a), s = sin(a);
    return float2x2(c, -s, s, c);
}

// 1つの星: 逆距離減衰のコア + 回折スパイク十字(45°回転の弱い2本目つき)
float StarShape(float2 v, float flare)
{
    float d = max(length(v), 1e-4f);
    float m = 0.035f / d;                                   // シャープな輝核
    float rayFall = smoothstep(0.55f, 0.05f, d);            // スパイクは星の近傍だけ
    float rays = max(0.0f, 1.0f - abs(v.x * v.y * 900.0f)); // 縦横スパイク
    m += rays * flare * rayFall;
    v = mul(Rot(0.7853982f), v);
    rays = max(0.0f, 1.0f - abs(v.x * v.y * 900.0f));       // 斜めスパイク(弱)
    m += rays * 0.35f * flare * rayFall;
    m *= smoothstep(0.9f, 0.15f, d);                        // セル外へ漏らさない
    return m;
}

// 星空1層: 3x3近傍セル走査(境界で星が切れない)。色温度も星ごとに変える
float3 StarField(float2 wp, float cellSize, float t, float seedOfs, float flareAmt)
{
    float3 acc = 0;
    float2 g  = wp / cellSize;
    float2 id = floor(g);
    float2 f  = frac(g);
    [unroll] for (int yy = -1; yy <= 1; yy++)
    [unroll] for (int xx = -1; xx <= 1; xx++)
    {
        float2 ofs = float2(xx, yy);
        float2 ci  = id + ofs;
        float  h   = hash21(ci + seedOfs);
        if (h < 0.74f) continue;                            // 星の密度
        float2 sp  = float2(hash21(ci + seedOfs + 7.7f), hash21(ci + seedOfs + 3.1f));
        float2 v   = ofs + sp - f;
        float  sz  = (h - 0.74f) / 0.26f;                   // 星の格(大きさ)
        float  tw  = 0.6f + 0.4f * sin(t * (1.0f + 3.0f * h) + h * 44.0f);
        float  fl  = flareAmt * sz * sz * (0.4f + 0.6f * tw); // 明るい星ほどスパイク
        float  m   = StarShape(v, fl) * lerp(0.12f, 1.0f, sz) * tw;
        float3 tint = lerp(float3(0.65f, 0.80f, 1.0f),      // 青白
                           float3(1.0f, 0.90f, 0.72f),      // 琥珀
                           hash21(ci + seedOfs + 5.5f));
        acc += tint * m;
    }
    return acc;
}

// 流れ星: 10レーン。位置/角度/長さ/周期は周回ごとにランダム、常に画面内に出現
float3 Meteors(float2 wp, float beats, float t)
{
    float3 acc = 0;
    [unroll] for (int i = 0; i < 14; i++)
    {
        float fi   = (float)i;
        float rate = 0.13f + 0.05f * hash21(float2(fi, 1.3f)); // 1周期 ≈ 5〜8拍
        float ph   = beats * rate + hash21(float2(fi, 8.6f)) * 13.7f;
        float cyc  = floor(ph);
        float tt   = frac(ph);
        const float life = 0.32f;                              // 周期の前半だけ飛ぶ
        if (tt > life) continue;
        float  lt  = tt / life;
        float2 sd  = float2(fi * 1.91f, cyc);
        float  h1 = hash21(sd),        h2 = hash21(sd + 4.2f);
        float  h3 = hash21(sd + 9.4f), h4 = hash21(sd + 6.1f);
        float2 p0  = float2(lerp(-26.0f, 4.0f, h1), lerp(2.0f, 11.2f, h2)); // 可視域内
        float  ang = lerp(-0.35f, -0.75f, h3);                 // 右下がり20°〜43°
        float2 dir = float2(cos(ang), sin(ang));
        float  len = lerp(5.0f, 11.0f, h4);
        float2 hp  = p0 + dir * lt * len;                      // 頭の現在位置
        float2 rel = wp - hp;
        float  s   = dot(rel, dir);                            // 進行方向成分(負=尾)
        float  q   = dot(rel, float2(-dir.y, dir.x));          // 垂直成分
        float  tailLen = 2.5f + 3.5f * h4;
        float  along = (s < 0.0f) ? saturate(1.0f + s / tailLen) : 0.0f;
        along *= along;                                        // 尾は先細り
        float  thin  = exp(-q * q * 55.0f) + 0.25f * exp(-q * q * 6.0f); // 芯+淡いグロー
        float  head  = exp(-dot(rel, rel) * 18.0f) * 1.2f;     // 頭の輝点
        float  sprk  = 0.85f + 0.15f * sin(s * 14.0f + t * 25.0f + fi * 17.0f); // 尾のきらめき
        float  env   = sin(3.14159f * lt);                     // 出現/消滅フェード
        float3 mcol  = lerp(float3(1.0f, 0.82f, 0.45f), float3(1, 1, 1), saturate(head));
        acc += mcol * (along * thin * sprk * 0.55f + head) * env;
    }
    return acc;
}

// 時計の針1本のSDF。dir方向に len、逆側に tail(カウンターウェイト)。幅は根元w0→先端w1
float HandSDF(float2 cd, float2 dir, float len, float tail, float w0, float w1)
{
    float v = dot(cd, dir);                          // 針方向成分
    float u = dot(cd, float2(-dir.y, dir.x));        // 垂直成分
    float k = saturate((v + tail) / (len + tail));
    float w = lerp(w0, w1, k);                       // ドフィーヌ風テーパー
    float dAxis = abs(u) - w;
    float dCap  = max(-(v + tail), v - len);
    return max(dAxis, dCap);
}

float4 PSMain(PSInput input) : SV_TARGET
{
    float2 wp = input.worldPos.xy;

    float beats = (effectValue > 0.0001f) ? effectValue : time * 2.133333f;
    float inten = shaderParams.x;
    if (effectValue <= 0.0001f && inten <= 0.0001f) inten = 0.6f;  // エディタ自走
    float amp    = 1.15f * inten;
    float pulse  = exp(-frac(beats) * 5.0f) * amp;          // 拍頭
    float accent = exp(-frac(beats * 0.25f) * 10.0f) * amp; // 小節頭

    // ── 1. ベース: 縦グラデ + FBM星雲 ──────────────────────────
    float grad = saturate((wp.y + 4.0f) / 24.0f);
    float3 col = lerp(float3(0.022f, 0.032f, 0.070f),   // 地平線側: ネイビー
                      float3(0.008f, 0.007f, 0.032f),   // 天頂側: 暗い藍
                      grad);

    float2 np  = wp * 0.16f + float2(time * 0.015f, -time * 0.006f);
    float  n1  = fbm(np);
    float  n2  = fbm(np * 1.7f + 31.0f);
    float  neb = smoothstep(0.50f, 0.95f, n1);
    float3 nebCol = lerp(float3(0.02f, 0.10f, 0.13f),   // ティール
                         float3(0.10f, 0.04f, 0.17f),   // 紫
                         smoothstep(0.3f, 0.7f, n2));
    col += nebCol * neb * (0.20f + 0.18f * pulse);

    // ── 2. 星空2層 + 流れ星(タイトル点灯 params.x と同時に開く) ──
    float t   = time;
    float lit = smoothstep(0.35f, 0.9f, inten);   // イントロ中(0.25)=0、サビ点灯(1.0)=1
    float skyM = smoothstep(-2.0f, 3.5f, wp.y);   // 地平線の下は星を薄く
    col += StarField(wp + float2(t * 0.10f, 0), 1.7f, t, 0.0f, 1.0f) * 0.24f * lit * skyM;
    col += StarField(wp * 0.55f + float2(t * 0.04f, 3.0f), 1.9f, t * 0.7f, 11.0f, 0.4f) * 0.13f * lit * skyM;
    col += Meteors(wp, beats, t) * lit;

    // ── 3. ロゴ裏ハロ(拍で息づく) ──────────────────────────────
    float2 lc = float2(-10.0f, 4.1f);
    float2 dv = (wp - lc) * float2(0.45f, 1.0f);
    float  halo = exp(-dot(dv, dv) * 0.015f);
    col += float3(0.032f, 0.058f, 0.115f) * halo * (0.7f + 0.45f * pulse + 0.3f * accent);

    // ── 4. 時計文字盤(シークバーの円環版)。ロゴを額装する2重リング ──
    float2 cd   = wp - lc;
    float  r    = length(cd);
    float  ang  = atan2(cd.y, cd.x);                       // -π..π
    const float TAU = 6.2831853f;
    float  R    = 7.0f;                                    // 時計全体が必ず画面内に収まる半径
    float  dial = 0.0f;
    // 外リング + 内リング(細く)
    dial += exp(-abs(r - R) * 5.0f) * 0.85f;
    dial += exp(-abs(r - 4.8f) * 8.0f) * 0.35f;
    // 60目盛(5目盛ごとに長い)。リング近傍のみ
    float tickA  = frac(ang / TAU * 60.0f);
    float tick   = smoothstep(0.10f, 0.0f, min(tickA, 1.0f - tickA));
    float major  = frac(ang / TAU * 12.0f);
    float majorT = smoothstep(0.035f, 0.0f, min(major, 1.0f - major));
    float band   = 1.0f - smoothstep(0.25f, 1.0f, abs(r - R));  // 逆順smoothstepはこのコンパイラで壊れる
    float bandL  = 1.0f - smoothstep(0.4f, 1.5f, abs(r - R));
    dial += tick * band * 0.5f + majorT * bandL * 0.9f;
    float3 dialCol = float3(0.16f, 0.34f, 0.50f);          // 淡いシアン鋼
    col += dialCol * dial * (0.10f + 0.07f * pulse) * lit * smoothstep(-1.0f, 1.5f, wp.y);

    // ── 時計の針(ドフィーヌ風2針 + クオーツ秒針)。12時起点・時計回り ──
    // 秒針は1拍=1ティック(22.5°)、easeOutBackで「カチッ」と跳ぶ。16拍1周=シークバーモチーフ継承
    float tickF = frac(beats);
    float pQ    = saturate(tickF / 0.14f);
    float qb    = pQ - 1.0f;
    float tickE = 1.0f + qb * qb * (2.70158f * qb + 1.70158f);
    float revS  = (floor(beats) + tickE) / 16.0f;
    float revM  = beats / 64.0f;                     // 分針: 64拍で1周
    float revH  = beats / 768.0f;                    // 時針: その1/12
    float2 dS   = float2(sin(revS * TAU), cos(revS * TAU));
    float2 dM   = float2(sin(revM * TAU), cos(revM * TAU));
    float2 dH   = float2(sin(revH * TAU), cos(revH * TAU));

    // 落ち影(針をまとめて右下にずらして評価 → 壁から浮いて見える)
    float2 cs = cd - float2(0.13f, -0.17f);
    float shd = smoothstep(0.08f, -0.08f, HandSDF(cs, dH, 2.6f, 0.7f, 0.22f, 0.08f));
    shd = max(shd, smoothstep(0.08f, -0.08f, HandSDF(cs, dM, 4.6f, 0.9f, 0.17f, 0.05f)));
    shd = max(shd, smoothstep(0.06f, -0.06f, HandSDF(cs, dS, 5.6f, 1.5f, 0.06f, 0.06f)));
    shd = max(shd, smoothstep(0.05f, -0.05f, length(cs) - 0.34f));
    col *= 1.0f - shd * 0.45f * lit;

    // 針の塗り(不透明合成)。先端に向かって明るく=金属のシアー
    // 色はムーンライトシルバー/アイスシアン(金のタイトルと被らない寒色系)
    float handA = 0.95f * lit;                       // タイトル点灯と同時に時計が現れる
    const float aa = 0.05f;
    float hHour = smoothstep(aa, -aa, HandSDF(cd, dH, 2.6f, 0.7f, 0.20f, 0.07f));
    float hMin  = smoothstep(aa, -aa, HandSDF(cd, dM, 4.6f, 0.9f, 0.15f, 0.04f));
    float hSec  = smoothstep(0.04f, -0.04f, HandSDF(cd, dS, 5.6f, 1.5f, 0.045f, 0.045f));
    float cw    = smoothstep(0.07f, -0.045f, abs(length(cd + dS * 1.9f) - 0.26f) - 0.065f); // 錘の輪
    float3 silver = float3(0.30f, 0.38f, 0.52f);     // ムーンライトシルバー(時分針)
    float3 ice    = float3(0.35f, 0.62f, 0.82f);     // アイスシアン(秒針)
    float kH = saturate(dot(cd, dH) / 2.6f);
    float kM = saturate(dot(cd, dM) / 4.6f);
    col = lerp(col, silver * (0.70f + 0.55f * kH), hHour * handA);
    col = lerp(col, silver * (0.70f + 0.55f * kM), hMin  * handA);
    col = lerp(col, ice, max(hSec, cw) * handA);
    // 秒針の先端グロー + 背後の薄いレーダー残光
    float2 tip = cd - dS * 5.6f;
    col += float3(0.65f, 0.90f, 1.0f) * exp(-dot(tip, tip) * 10.0f) * (0.25f + 0.45f * pulse) * lit;
    float phiS   = 1.5707963f - revS * TAU;
    float sweepA = frac((ang - phiS) / TAU);
    float discM  = (1.0f - smoothstep(R - 1.2f, R + 0.4f, r)) * smoothstep(1.0f, 3.5f, r);
    col += float3(0.30f, 0.65f, 0.90f) * exp(-sweepA * 26.0f) * discM * (0.035f + 0.06f * accent) * lit;
    // 中央ハブ(銀キャップ+軸点)。拍でほんのり明滅
    float hub    = smoothstep(0.05f, -0.05f, r - 0.36f);
    float hubDot = smoothstep(0.03f, -0.03f, r - 0.12f);
    col = lerp(col, silver * (0.9f + 0.5f * pulse), hub * handA);
    col = lerp(col, float3(0.05f, 0.055f, 0.09f), hubDot * handA);

    // ── 6. 斜めシマー(旧来の流れは弱めて残す) ──────────────────
    float sh = sin((wp.x + wp.y) * 0.5f - beats * 0.3927f) * 0.5f + 0.5f;
    sh = pow(sh, 6.0f);
    col += float3(0.012f, 0.028f, 0.05f) * sh * (0.30f + 1.0f * pulse + 0.6f * accent);

    // ── 7. 地平線グロー(床との継ぎ目をシアンで発光) ─────────────
    float hg = exp(-max(wp.y, 0.0f) * 0.55f) * smoothstep(-3.0f, 0.0f, wp.y);
    col += float3(0.018f, 0.062f, 0.088f) * hg * (0.7f + 0.4f * pulse);

    // ── 8. 拍リフト + ビネット + サビ頭フラッシュ ───────────────
    col += float3(0.006f, 0.010f, 0.018f) * pulse + float3(0.005f, 0.008f, 0.016f) * accent;
    float2 vp = (wp - float2(-10.0f, 3.0f)) / float2(24.0f, 14.0f);
    col *= 1.0f - 0.45f * saturate(dot(vp, vp) - 0.15f);
    col += float3(0.70f, 0.82f, 1.0f) * shaderParams.y;

    return float4(col, 1.0f);   // 背景幕は常に不透明(スカイ透け防止)
}
