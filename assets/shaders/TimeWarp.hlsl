// TimeWarp.hlsl -- 時間操作されているオブジェクト用の共通メッシュシェーダー。
// Lua側から scene:setMeshEffect(entity, v) で状態を受け取る:
//   v == 0        : 通常(ただのランバート描画)
//   0 < v <= 1.5  : 早送り中(強度=v)。シアンの帯が上へ高速スクロール+横ジッタ残像+
//                   強度0.55超でディザ半透明(実体がない「経由中」の表現)
//   2 <= v < 4    : 後戻り中(強度=v-2)。紫の帯が下へ逆スクロール+VHS風走査線+色反転パルス
//   4.5<= v <=5.5 : 【的アピール】矢を当てられるオブジェクトの常時ゆらめき(金色のパルス)。
//                   これが光っていない物は撃っても無反応=判別ルール
//   6.0<= v < 7.0 : 【経年劣化】v-6.0=劣化度。錆がノイズ状に侵食し、ヒビ(黒い筋+熾火の
//                   オレンジ)が走り、劣化が進むと表面がディザで欠け落ちる。金パルス内蔵
// 帯のスクロール方向と色(シアン=進む/紫=戻る/金=撃てる)で時間の向きを言語化する。

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
    float3 pos = input.position;

    // 早送り中は小刻みな横揺れ(コマ落ちしたような震え)を頂点にかける
    float ff = (effectValue > 0.0f && effectValue < 1.5f) ? saturate(effectValue) : 0.0f;
    if (ff > 0.0f)
        pos.x += sin(time * 47.0f + pos.y * 6.0f) * 0.03f * ff;

    output.positionSV  = mul(float4(pos, 1.0f), mvp);
    output.worldNormal = normalize(mul(input.normal, (float3x3)model));
    output.color       = input.color;
    output.texCoord    = input.texCoord;
    output.worldPos    = mul(float4(input.position, 1.0f), model).xyz;
    return output;
}

// 安価な2Dバリューノイズ(錆の斑・ヒビ用)
float hash2(float2 p)
{
    return frac(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453f);
}
float vnoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0f - 2.0f * f);
    float a = hash2(i);
    float b = hash2(i + float2(1, 0));
    float c = hash2(i + float2(0, 1));
    float d = hash2(i + float2(1, 1));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float4 PSMain(PSInput input) : SV_TARGET
{
    float ff = (effectValue > 0.0f && effectValue < 1.5f) ? saturate(effectValue) : 0.0f;
    float rw = (effectValue >= 2.0f && effectValue < 4.0f) ? saturate(effectValue - 2.0f) : 0.0f;
    float tg = (effectValue >= 4.5f && effectValue <= 5.5f) ? 1.0f : 0.0f;

    // 早送り: 残像っぽくUVを横に複製ずらしして混ぜる
    float2 uv = input.texCoord;
    float4 albedo = g_albedo.Sample(g_sampler, uv);
    if (ff > 0.0f)
    {
        float4 ghost = g_albedo.Sample(g_sampler, uv + float2(sin(time * 31.0f) * 0.04f * ff, 0));
        albedo = lerp(albedo, ghost, 0.45f);
    }
    albedo *= input.color;

    float3 N = normalize(input.worldNormal);
    float3 L = normalize(-lightDir);
    float  ndotl = max(dot(N, L), 0.0f);
    float3 lit = albedo.rgb * (lightColor * ndotl + ambientStrength);

    // ワールドYベースの帯: 早送り=上へ高速 / 後戻り=下へ(向きの言語化)。UVに依存しない
    float wy = input.worldPos.y;
    if (ff > 0.0f)
    {
        float band = saturate(sin((wy * 3.0f - time * 9.0f) * 6.2831853f) * 0.5f + 0.5f);
        band = pow(band, 5.0f);
        lit += float3(0.25f, 0.85f, 1.0f) * band * (0.8f + 0.8f * ff);
        lit += float3(0.1f, 0.4f, 0.55f) * ff * 0.5f;   // 全体をシアンに寄せる

        // 強い早送り=実体がない: 市松ディザで抜いて半透明に見せる
        if (ff > 0.55f)
        {
            uint2 p = uint2(input.positionSV.xy);
            if (((p.x + p.y) & 1) == 0)
                discard;
        }
    }
    if (rw > 0.0f)
    {
        float band = saturate(sin((wy * 3.0f + time * 4.5f) * 6.2831853f) * 0.5f + 0.5f);
        band = pow(band, 5.0f);
        lit += float3(0.62f, 0.35f, 1.0f) * band * (0.7f + 0.7f * rw);

        // VHS巻き戻し風の細い走査線(スクリーン空間)
        float scan = frac(input.positionSV.y * 0.14f + time * 3.0f);
        if (scan < 0.12f)
            lit += float3(0.5f, 0.3f, 0.9f) * 0.6f * rw;

        // 時折ネガ反転がパルスする(過去へ戻るフラッシュバック)
        float pulse = saturate(sin(time * 5.0f) * 0.5f + 0.5f);
        lit = lerp(lit, float3(1.0f, 1.0f, 1.0f) - lit, 0.18f * rw * pulse);
    }

    // 【経年劣化】錆の侵食+ヒビ+欠け落ち。deg=0でほぼ新品、1でぼろぼろ
    if (effectValue >= 6.0f && effectValue < 7.0f)
    {
        float deg = saturate(effectValue - 6.0f);
        float2 wp = input.worldPos.xy;

        // 錆の斑: ノイズしきい値が劣化度で下がる=錆が面で広がっていく
        float rust = vnoise(wp * 3.1f) * 0.65f + vnoise(wp * 9.7f) * 0.35f;
        if (rust < deg * 0.85f)
        {
            float3 rustCol = float3(0.45f, 0.2f, 0.08f) * (0.7f + 0.6f * vnoise(wp * 17.0f));
            lit = lerp(lit, rustCol, 0.75f);
        }

        // ヒビ: ノイズの等高線を細く抜く。奥に熾火のオレンジが明滅
        float vein = abs(vnoise(wp * 5.3f) - 0.5f);
        float crackW = 0.015f + 0.05f * deg;
        if (vein < crackW && deg > 0.15f)
        {
            float ember = 0.5f + 0.5f * sin(time * 7.0f + wp.x * 9.0f);
            lit = lerp(lit, float3(0.05f, 0.03f, 0.02f), 0.85f);
            lit += float3(1.0f, 0.45f, 0.1f) * ember * deg * 0.9f;
        }

        // 欠け落ち: 劣化が進むほど表面がディザで抜けてボロボロに見える
        float crumble = vnoise(wp * 13.0f + float2(0.0f, time * 0.15f));
        if (deg > 0.45f && crumble > 1.0f - (deg - 0.45f) * 0.5f)
        {
            uint2 pp = uint2(input.positionSV.xy);
            if (((pp.x + pp.y) & 1) == 0)
                discard;
        }

        // 金パルス内蔵(撃てる印は維持しつつ、劣化するほど鈍く)
        float band6 = saturate(sin((input.worldPos.y * 2.2f - time * 1.6f) * 6.2831853f) * 0.5f + 0.5f);
        band6 = pow(band6, 8.0f);
        lit += float3(1.0f, 0.82f, 0.35f) * band6 * 0.45f * (1.0f - deg * 0.6f);
    }

    // 【照準ロック】構え中に狙われている対象: モード色で強く点滅(8.x=先送り/9.x=後戻し)
    if (effectValue >= 8.0f && effectValue < 10.0f)
    {
        bool isRw = (effectValue >= 9.0f);
        float blink = 0.55f + 0.45f * sin(time * 10.0f);
        float3 mc = isRw ? float3(0.62f, 0.35f, 1.0f) : float3(0.25f, 0.85f, 1.0f);
        lit = lerp(lit, mc, 0.35f * blink);
        float edge = saturate(sin((input.worldPos.y * 4.0f + time * 6.0f) * 6.2831853f) * 0.5f + 0.5f);
        lit += mc * pow(edge, 6.0f) * 0.8f;
    }

    // 【的アピール】撃てるオブジェクトは金色の細い帯がゆっくり上り、全体が淡く脈動する
    if (tg > 0.0f)
    {
        float wy2  = input.worldPos.y;
        float band = saturate(sin((wy2 * 2.2f - time * 1.6f) * 6.2831853f) * 0.5f + 0.5f);
        band = pow(band, 8.0f);
        float pulse = 0.5f + 0.5f * sin(time * 2.6f);
        lit += float3(1.0f, 0.82f, 0.35f) * band * 0.55f;
        lit += float3(0.5f, 0.42f, 0.15f) * (0.10f + 0.10f * pulse);
    }

    return float4(lit, albedo.a);
}
